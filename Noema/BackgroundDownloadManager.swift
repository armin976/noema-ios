import Foundation

#if os(macOS)
import AppKit
#endif

#if canImport(BackgroundTasks) && !os(visionOS) && !os(macOS)
import BackgroundTasks
#endif

// Thread-safe, monotonic throttler to limit how often we emit progress updates.
private final class ProgressThrottler<Key: Hashable> {
    private let minimumInterval: Double
    private var lastFireSeconds: [Key: Double] = [:]
    private let lock = NSLock()

    init(interval: TimeInterval) {
        self.minimumInterval = interval
    }

    func shouldAllow(key: Key, force: Bool = false) -> Bool {
        let nowSeconds = Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
        lock.lock()
        defer { lock.unlock() }

        if force {
            lastFireSeconds[key] = nowSeconds
            return true
        }

        if let last = lastFireSeconds[key], (nowSeconds - last) < minimumInterval {
            return false
        }

        lastFireSeconds[key] = nowSeconds
        return true
    }

    func clear(key: Key) {
        lock.lock()
        lastFireSeconds.removeValue(forKey: key)
        lock.unlock()
    }
}

/// Manages large downloads that should continue while the app is suspended or terminated.
/// Uses a background URLSession with a fixed identifier and exposes a simple async API.
@MainActor
final class BackgroundDownloadManager: NSObject {
    static let shared = BackgroundDownloadManager()

    private struct TaskRecord: Codable {
        let destination: URL
        let expectedSize: Int64?
        /// When resuming from partial downloads, store the already-downloaded byte count so we can
        /// report accurate absolute progress instead of only the remaining segment.
        let resumeOffset: Int64?
    }

    private let sessionIdentifier = "com.noema.background-download"
    #if canImport(BackgroundTasks) && !os(visionOS) && !os(macOS)
    private let maintenanceTaskIdentifier = "com.noema.download.maintenance"
    #endif

    // Background-capable session (keeps downloads running when suspended)
    private lazy var backgroundSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
        // Keep the system from deferring downloads unnecessarily
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.waitsForConnectivity = true
        config.allowsCellularAccess = true
        config.allowsConstrainedNetworkAccess = true
        config.allowsExpensiveNetworkAccess = true
        // Allow more parallel connections for cases where multiple assets fetch concurrently (e.g., mmproj + weights)
        config.httpMaximumConnectionsPerHost = 8
        #if os(iOS) || os(tvOS) || os(watchOS)
        if #available(iOS 15.0, tvOS 15.0, watchOS 8.0, *) {
            config.multipathServiceType = .handover
        }
        #endif
        let s = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        NetworkKillSwitch.track(session: s)
        return s
    }()

    // Fast foreground session used while the app is active; noticeably improves throughput
    private lazy var foregroundSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.waitsForConnectivity = true
        cfg.allowsCellularAccess = true
        cfg.allowsConstrainedNetworkAccess = true
        cfg.allowsExpensiveNetworkAccess = true
        cfg.httpMaximumConnectionsPerHost = 12
        cfg.httpShouldUsePipelining = true
        let s = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
        NetworkKillSwitch.track(session: s)
        return s
    }()

    /// Keyed by (session identifier, task identifier) so foreground/background
    /// sessions running concurrently do not trample each other's bookkeeping.
    private struct TaskKey: Hashable {
        let sessionID: String
        let taskID: Int
    }

    // Throttle progress events to ~10 Hz per download to avoid flooding the main actor.
    nonisolated(unsafe) private let progressThrottler = ProgressThrottler<TaskKey>(interval: 0.1)

    private var destinations: [TaskKey: URL] = [:]
    private var completions: [TaskKey: (Result<URL, Error>) -> Void] = [:]
    private var progressHandlers: [TaskKey: (Double) -> Void] = [:]
    private var expectedSizes: [TaskKey: Int64] = [:]
    private var progressBytesHandlers: [TaskKey: (Int64, Int64) -> Void] = [:]
    // Bytes that were already downloaded before a resumed task was created.
    private var resumeOffsets: [TaskKey: Int64] = [:]
    private var backgroundCompletionHandler: (() -> Void)?
    // Map destination path → current task key
    private var taskIdByDestination: [String: TaskKey] = [:]
    // Resume data captured when pausing, keyed by destination path
    private var resumeDataStore: [String: Data] = [:]
    private enum SessionKind { case foreground, background }
    private var lastSessionChoice: SessionKind? = nil
    private var lifecycleObservers: [NSObjectProtocol] = []

    private override init() {
        super.init()
        installLifecycleObservers()
        #if canImport(BackgroundTasks) && !os(visionOS) && !os(macOS)
        registerBackgroundTask()
        #endif
        restorePersistedTasks()
    }

    // Build a stable key for tracking tasks across multiple URLSessions.
    nonisolated private func key(for session: URLSession, taskID: Int) -> TaskKey {
        let id = session.configuration.identifier ?? "foreground"
        return TaskKey(sessionID: id, taskID: taskID)
    }

    private func installLifecycleObservers() {
#if canImport(UIKit)
        let center = NotificationCenter.default
        lifecycleObservers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            Task { await logger.log("[Download][App] didEnterBackground – downloads will favor background URLSession") }
        })
        lifecycleObservers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            Task { await logger.log("[Download][App] willEnterForeground") }
        })
        lifecycleObservers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { await logger.log("[Download][App] didBecomeActive – downloads will prefer foreground URLSession") }
        })
#endif
#if os(macOS)
        let center = NotificationCenter.default
        lifecycleObservers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { await logger.log("[Download][App] didBecomeActive (macOS)") }
        })
        lifecycleObservers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            Task { await logger.log("[Download][App] didResignActive (macOS)") }
        })
#endif
    }

    private func logSessionChoice(kind: SessionKind, reason: String) {
        guard lastSessionChoice != kind else { return }
        lastSessionChoice = kind
        let label = (kind == .foreground) ? "foreground" : "background"
        Task { await logger.log("[Download][Session] now using \(label) session (\(reason))") }
    }

    // MARK: - Public API
    /// Start a download that can continue in the background.
    @discardableResult
    func download(from remote: URL,
                  to local: URL,
                  expectedSize: Int64? = nil,
                  progress: ((Double) -> Void)? = nil,
                  progressBytes: ((Int64, Int64) -> Void)? = nil) async throws -> URL {
        var req = URLRequest(url: remote)
        return try await download(request: req, to: local, expectedSize: expectedSize, progress: progress, progressBytes: progressBytes)
    }

    /// Start a download with a custom request (headers/auth supported).
    @discardableResult
    func download(request: URLRequest,
                  to local: URL,
                  expectedSize: Int64? = nil,
                  progress: ((Double) -> Void)? = nil,
                  progressBytes: ((Int64, Int64) -> Void)? = nil) async throws -> URL {
        // Try to refine the expected size with a HEAD request; this fixes UI lag when registry
        // metadata overestimates the real file size. We only do this for the initial call
        // (resume path below already has a persisted expectedSize).
        let headLength = await remoteContentLength(for: request)
        let refinedExpected: Int64? = {
            if let head = headLength, head > 0 { return head }
            return expectedSize
        }()

        return try await withCheckedThrowingContinuation { cont in
            // If we have resume data for this destination, prefer resuming
            let session = self.preferredSession()
            let sessionLabel = (session.configuration.identifier == self.sessionIdentifier) ? "background" : "foreground"
            let expectedLabel: String = {
                if let refinedExpected, refinedExpected > 0 {
                    return ByteCountFormatter.string(fromByteCount: refinedExpected, countStyle: .file)
                }
                return "unknown"
            }()
            Task { await logger.log("[Download][Session] start dest=\(local.lastPathComponent) session=\(sessionLabel) expected=\(expectedLabel)") }

            if let resume = resumeDataStore[local.path] {
                let offset = Self.extractResumeOffset(from: resume)
                let task = session.downloadTask(withResumeData: resume)
                let record = TaskRecord(destination: local, expectedSize: refinedExpected, resumeOffset: offset > 0 ? offset : nil)
                if let data = try? JSONEncoder().encode(record) {
                    task.taskDescription = String(data: data, encoding: .utf8)
                }
                let key = self.key(for: session, taskID: task.taskIdentifier)
                destinations[key] = record.destination
                taskIdByDestination[local.path] = key
                if let expected = record.expectedSize { expectedSizes[key] = expected }
                if offset > 0 { resumeOffsets[key] = offset }
                if let progress = progress { progressHandlers[key] = progress }
                if let progressBytes = progressBytes { progressBytesHandlers[key] = progressBytes }
                completions[key] = { cont.resume(with: $0) }
                resumeDataStore.removeValue(forKey: local.path)
                task.resume()
                return
            }

            let task = session.downloadTask(with: request)
            let record = TaskRecord(destination: local, expectedSize: refinedExpected, resumeOffset: nil)
            if let data = try? JSONEncoder().encode(record) {
                task.taskDescription = String(data: data, encoding: .utf8)
            }
            let key = self.key(for: session, taskID: task.taskIdentifier)
            destinations[key] = record.destination
            taskIdByDestination[local.path] = key
            if let expected = record.expectedSize { expectedSizes[key] = expected }
            if let progress = progress { progressHandlers[key] = progress }
            if let progressBytes = progressBytes { progressBytesHandlers[key] = progressBytes }
            completions[key] = { cont.resume(with: $0) }
            task.resume()
        }
    }

    /// Called from AppDelegate when the system wakes us for background events.
    func handleEvents(for identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == sessionIdentifier else { completionHandler(); return }
        _ = backgroundSession // ensure the background session is instantiated so the system can deliver events
        restorePersistedTasks()
        backgroundCompletionHandler = completionHandler
    }

    /// Pause an in‑flight background download targeting the given destination.
    /// Stores resume data so a subsequent `download` call will resume.
    func pause(destination: URL, completion: (() -> Void)? = nil) {
        guard let taskID = taskIdByDestination[destination.path] else { completion?(); return }
        guard let task = currentDownloadTasksSnapshot()[taskID] else { completion?(); return }
        task.cancel(byProducingResumeData: { [weak self] data in
            Task { @MainActor in
                if let d = data { self?.resumeDataStore[destination.path] = d }
                completion?()
            }
        })
    }

    /// Cancel and discard resume data for a destination.
    func cancel(destination: URL) {
        resumeDataStore.removeValue(forKey: destination.path)
        if let taskID = taskIdByDestination[destination.path], let task = currentDownloadTasksSnapshot()[taskID] {
            task.cancel()
        }
    }

    // MARK: - BGTaskScheduler
    #if canImport(BackgroundTasks) && !os(visionOS) && !os(macOS)
    private func registerBackgroundTask() {
        // Deliver the handler on the main queue to avoid libdispatch queue
        // assertions when the system wakes us on a maintenance queue after
        // long idle periods. Our manager is @MainActor‑isolated, so always hop
        // to the main actor before touching state or URLSession.
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: maintenanceTaskIdentifier,
            using: .main
        ) { [weak self] task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor [weak self] in
                self?.handleMaintenance(task: processingTask)
            }
        }
    }

    func scheduleMaintenance() {
        let request = BGProcessingTaskRequest(identifier: maintenanceTaskIdentifier)
        request.requiresNetworkConnectivity = true
        do { try BGTaskScheduler.shared.submit(request) } catch {
            // Non-fatal; background tasks are best-effort.
            print("Failed to submit BGProcessingTask: \(error)")
        }
    }

    private func handleMaintenance(task: BGProcessingTask) {
        scheduleMaintenance() // Always reschedule for next time
        backgroundSession.getAllTasks { _ in
            // Reconcile stalled tasks or perform cleanup as needed.
            task.setTaskCompleted(success: true)
        }
    }
    #else
    func scheduleMaintenance() {
        // BGProcessingTask isn't supported on visionOS or macOS. Downloads
        // still work while the scene is active thanks to the background
        // URLSession.
    }
    #endif

    private func restorePersistedTasks() {
        backgroundSession.getAllTasks { [weak self] tasks in
            Task { @MainActor [weak self] in
                guard let self else { return }
                for task in tasks {
                    guard let record = self.record(for: task.taskDescription) else { continue }
                    let key = self.key(for: self.backgroundSession, taskID: task.taskIdentifier)
                    self.destinations[key] = record.destination
                    self.taskIdByDestination[record.destination.path] = key
                    if let expected = record.expectedSize {
                        self.expectedSizes[key] = expected
                    }
                    if let offset = record.resumeOffset, offset > 0 {
                        self.resumeOffsets[key] = offset
                    }
                }
            }
        }
    }

    // Snapshot of download tasks keyed by identifier for quick lookup from @MainActor
    private func currentDownloadTasksSnapshot() -> [TaskKey: URLSessionDownloadTask] {
        // Query both sessions separately and merge results for a full snapshot
        let group = DispatchGroup()
        var bg: [URLSessionTask] = []
        var fg: [URLSessionTask] = []
        group.enter()
        backgroundSession.getAllTasks { tasks in
            bg = tasks
            group.leave()
        }
        group.enter()
        foregroundSession.getAllTasks { tasks in
            fg = tasks
            group.leave()
        }
        _ = group.wait(timeout: .now() + 1)

        var map: [TaskKey: URLSessionDownloadTask] = [:]
        for t in bg {
            if let d = t as? URLSessionDownloadTask {
                let key = key(for: backgroundSession, taskID: d.taskIdentifier)
                map[key] = d
            }
        }
        for t in fg {
            if let d = t as? URLSessionDownloadTask {
                let key = key(for: foregroundSession, taskID: d.taskIdentifier)
                map[key] = d
            }
        }
        return map
    }
}

// MARK: - URLSessionDownloadDelegate
extension BackgroundDownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession,
                                downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64,
                                totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        let taskID = downloadTask.taskIdentifier
        let key = self.key(for: session, taskID: taskID)

        // Allow the first callback immediately, throttle to 10 Hz afterward.
        // Always allow the final chunk even if it falls inside the throttle window.
        let isFinalChunk = totalBytesExpectedToWrite > 0 && totalBytesWritten >= totalBytesExpectedToWrite
        guard progressThrottler.shouldAllow(key: key, force: isFinalChunk) else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let offset = self.resumeOffsets[key] ?? 0

            // Some servers report only the *remaining* bytes for resumed downloads. Combine any
            // previously-downloaded offset with the current callback to compute an absolute total.
            // Prefer the server-reported length (Content-Length) when available; fall back to the
            // caller-supplied expected size, without inflating via `max` to avoid overstating totals
            // when registry metadata overestimates the file size.
            let expectedFromTask = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
            let recordedExpected = self.expectedSizes[key]

            let fullExpected: Int64 = {
                if let expectedFromTask { return expectedFromTask + offset }
                if let recordedExpected { return recordedExpected }
                return (offset > 0) ? offset + totalBytesWritten : -1
            }()

            let writtenTotal = totalBytesWritten + offset

            if fullExpected > 0 {
                let fraction = Double(writtenTotal) / Double(fullExpected)
                self.progressHandlers[key]?(fraction)
                self.progressBytesHandlers[key]?(writtenTotal, fullExpected)
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession,
                                downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        let taskID = downloadTask.taskIdentifier
        let description = downloadTask.taskDescription
        let key = key(for: session, taskID: taskID)
        // Decode the destination synchronously and move the file immediately.
        guard let record = Self.decodeTaskRecordNonisolated(from: description) else {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.completions[key]?(.failure(URLError(.unknown)))
                self.cleanup(key: key)
            }
            return
        }
        let destination = record.destination
        // Ensure parent exists and move the temp file before returning from delegate
        do {
            let parent = destination.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            try FileManager.default.removeItemIfExists(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            Task { @MainActor [weak self] in
                await self?.finalizeSuccess(key: key, destination: destination)
            }
        } catch {
            Task { @MainActor [weak self] in
                await self?.finalizeFailure(key: key, error: error)
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession,
                                task: URLSessionTask,
                                didCompleteWithError error: Error?) {
        guard let error else { return }
        let taskID = task.taskIdentifier
        Task { @MainActor [weak self] in
            guard let self else { return }
            let key = self.key(for: session, taskID: taskID)
            self.completions[key]?(.failure(error))
            self.cleanup(key: key)
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor [weak self] in
            self?.backgroundCompletionHandler?()
            self?.backgroundCompletionHandler = nil
        }
    }

    @MainActor
    private func finalizeSuccess(key: TaskKey, destination: URL) async {
        if let completion = completions[key] {
            completion(.success(destination))
        } else {
            // No in-memory continuation (likely after app restart). Notify observers so
            // they can reconcile and finalize installation from the completed file.
            NotificationCenter.default.post(
                name: .backgroundDownloadCompleted,
                object: nil,
                userInfo: [
                    "destinationURL": destination,
                    "taskID": key.taskID
                ]
            )
        }
        cleanup(key: key)
    }

    @MainActor
    private func finalizeFailure(key: TaskKey, error: Error) async {
        if let completion = completions[key] {
            completion(.failure(error))
        } else {
            // Surface failure via notification so UI can reflect the error state.
            var info: [String: Any] = [
                "error": error,
                "taskID": key.taskID
            ]
            // Best-effort: include original URL if we can still see the task
            if let task = currentDownloadTasksSnapshot()[key], let url = task.originalRequest?.url {
                info["originalURL"] = url
            }
            if let dest = destinations[key] { info["destinationURL"] = dest }
            NotificationCenter.default.post(name: .backgroundDownloadCompleted, object: nil, userInfo: info)
        }
        cleanup(key: key)
    }

    @MainActor
    private func cleanup(key: TaskKey) {
        if let dest = destinations[key] {
            taskIdByDestination[dest.path] = nil
        }
        destinations[key] = nil
        progressThrottler.clear(key: key)
        completions[key] = nil
        progressHandlers[key] = nil
        progressBytesHandlers[key] = nil
        expectedSizes[key] = nil
        resumeOffsets[key] = nil
    }
}

extension BackgroundDownloadManager {
    /// Best-effort HEAD to learn the true Content-Length before starting a download.
    private func remoteContentLength(for request: URLRequest) async -> Int64? {
        var head = request
        head.httpMethod = "HEAD"
        head.timeoutInterval = 10
        let cfg = URLSessionConfiguration.ephemeral
        cfg.waitsForConnectivity = false
        cfg.allowsExpensiveNetworkAccess = true
        cfg.allowsConstrainedNetworkAccess = true
        let session = URLSession(configuration: cfg)
        do {
            let (_, resp) = try await session.data(for: head)
            guard let http = resp as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return nil }
            let len = http.expectedContentLength
            return len > 0 ? len : nil
        } catch {
            return nil
        }
    }

    @MainActor
    private func record(for taskDescription: String?) -> TaskRecord? {
        guard let desc = taskDescription,
              let data = desc.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TaskRecord.self, from: data)
    }

    // Nonisolated decoding helper so we can move the temp file synchronously inside the delegate.
    nonisolated private static func decodeTaskRecordNonisolated(from taskDescription: String?) -> TaskRecord? {
        guard let desc = taskDescription, let data = desc.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TaskRecord.self, from: data)
    }

    /// Choose the best session for the current app state: prefer a fast foreground session while
    /// the app is active, fall back to the background-capable session otherwise.
    private func preferredSession() -> URLSession {
        #if os(macOS)
        // macOS: use a foreground session so downloads start immediately and are visible in Xcode.
        // Background URLSessions on macOS can be deferred or require additional background modes.
        logSessionChoice(kind: .foreground, reason: "macOS")
        return foregroundSession
        #elseif canImport(UIKit)
        // iOS/tvOS/watchOS: prefer fast foreground when active, fall back to background when suspended.
        let state = UIApplication.sharedIfAvailable?.applicationState
        let stateLabel: String = {
            switch state {
            case .some(.active): return "active"
            case .some(.background): return "background"
            case .some(.inactive): return "inactive"
            default: return "unknown"
            }
        }()
        let kind: SessionKind = (state == .active) ? .foreground : .background
        let reason = "appState=\(stateLabel)"
        logSessionChoice(kind: kind, reason: reason)
        return kind == .foreground ? foregroundSession : backgroundSession
        #else
        logSessionChoice(kind: .background, reason: "platform default")
        return backgroundSession
        #endif
    }
}

// MARK: - Resume Data Helpers
private extension BackgroundDownloadManager {
    /// Extract the number of bytes that were already received from the URLSession resume data blob.
    /// The resume data format is an opaque plist keyed archive; we defensively try both modern and
    /// legacy keys to maximize compatibility across platforms.
    static func extractResumeOffset(from data: Data) -> Int64 {
        // 1) Attempt to parse as a property list dictionary
        if let plist = try? PropertyListSerialization.propertyList(from: data, options: PropertyListSerialization.ReadOptions(), format: nil) as? [String: Any] {
            if let n = plist["NSURLSessionResumeBytesReceived"] as? NSNumber { return n.int64Value }
            if let n = plist["_NSURLSessionResumeBytesReceived"] as? NSNumber { return n.int64Value }
        }

        // 2) Fallback to keyed unarchiver (older iOS/macOS versions)
        if let dict = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSDictionary.self, NSNumber.self, NSString.self, NSData.self], from: data) as? [String: Any] {
            if let n = dict["NSURLSessionResumeBytesReceived"] as? NSNumber { return n.int64Value }
            if let n = dict["_NSURLSessionResumeBytesReceived"] as? NSNumber { return n.int64Value }
        }

        return 0
    }
}

#if canImport(UIKit)
import UIKit
private extension UIApplication {
    static var sharedIfAvailable: UIApplication? {
        // Avoid accessing UIApplication in app extensions
        guard NSClassFromString("UIApplication") != nil else { return nil }
        return UIApplication.perform(NSSelectorFromString("sharedApplication"))?.takeUnretainedValue() as? UIApplication
    }
}
#endif

// FileManager helper is defined globally in Noema.swift
