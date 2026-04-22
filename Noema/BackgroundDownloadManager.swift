import Foundation

#if os(macOS)
import AppKit
#endif

#if canImport(BackgroundTasks) && !os(visionOS) && !os(macOS)
import BackgroundTasks
#endif

#if canImport(UIKit)
import UIKit
#endif

// Thread-safe, monotonic throttler to limit how often we emit progress updates.
enum DownloadProgressExpectationMode: String, Equatable {
    case freshTask
    case freshRecorded
    case resumeFullSize
    case resumeRemainingBytes
    case resumeFallback
    case resumeRecordedOnly
    case resumeNoRecorded
    case unknown
}

struct DownloadProgressNormalizationResult: Equatable {
    let writtenTotal: Int64
    let fullExpected: Int64
    let mode: DownloadProgressExpectationMode
}

struct BackgroundDownloadTaskSnapshot: Equatable, Sendable {
    let jobID: String?
    let artifactID: String?
    let destination: URL
    let resumeOffset: Int64
    let bytesReceived: Int64
    let taskExpectedBytes: Int64?
    let recordedExpectedBytes: Int64?
    let writtenTotal: Int64
    let fullExpected: Int64?
    let hasLiveTask: Bool
}

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
        let jobID: String?
        let artifactID: String?
        let destination: URL
        let expectedSize: Int64?
        /// When resuming from partial downloads, store the already-downloaded byte count so we can
        /// report accurate absolute progress instead of only the remaining segment.
        let resumeOffset: Int64?
        let appendsToExistingFile: Bool

        enum CodingKeys: String, CodingKey {
            case jobID
            case artifactID
            case destination
            case expectedSize
            case resumeOffset
            case appendsToExistingFile
        }

        init(jobID: String?,
             artifactID: String?,
             destination: URL,
             expectedSize: Int64?,
             resumeOffset: Int64?,
             appendsToExistingFile: Bool) {
            self.jobID = jobID
            self.artifactID = artifactID
            self.destination = destination
            self.expectedSize = expectedSize
            self.resumeOffset = resumeOffset
            self.appendsToExistingFile = appendsToExistingFile
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            jobID = try container.decodeIfPresent(String.self, forKey: .jobID)
            artifactID = try container.decodeIfPresent(String.self, forKey: .artifactID)
            destination = try container.decode(URL.self, forKey: .destination)
            expectedSize = try container.decodeIfPresent(Int64.self, forKey: .expectedSize)
            resumeOffset = try container.decodeIfPresent(Int64.self, forKey: .resumeOffset)
            appendsToExistingFile = try container.decodeIfPresent(Bool.self, forKey: .appendsToExistingFile) ?? false
        }
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
    private var loggedProgressModes: [TaskKey: DownloadProgressExpectationMode] = [:]
    private var backgroundCompletionHandler: (() -> Void)?
    // Map destination path → current task key
    private var taskIdByDestination: [String: TaskKey] = [:]
    private var taskRecordByKey: [TaskKey: TaskRecord] = [:]
    private var liveTasks: [TaskKey: URLSessionDownloadTask] = [:]
    private var liveSnapshots: [TaskKey: BackgroundDownloadTaskSnapshot] = [:]
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
            Task { await logger.log("[Download][App] didEnterBackground – durable transfers stay on background URLSession") }
        })
        lifecycleObservers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            Task { await logger.log("[Download][App] willEnterForeground") }
        })
        lifecycleObservers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { await logger.log("[Download][App] didBecomeActive – durable transfers stay on background URLSession") }
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

    private func resumeDataURL(for record: TaskRecord) -> URL? {
        guard let jobID = record.jobID, let artifactID = record.artifactID else { return nil }
        return DownloadPersistencePaths.resumeDataURL(jobID: jobID, artifactID: artifactID)
    }

    private func loadResumeData(for record: TaskRecord) -> Data? {
        if let cached = resumeDataStore[record.destination.path] {
            return cached
        }
        guard let url = resumeDataURL(for: record),
              let data = try? Data(contentsOf: url) else { return nil }
        resumeDataStore[record.destination.path] = data
        return data
    }

    private func persistResumeData(_ data: Data, for record: TaskRecord) {
        resumeDataStore[record.destination.path] = data
        guard let url = resumeDataURL(for: record) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func clearResumeData(for record: TaskRecord) {
        resumeDataStore.removeValue(forKey: record.destination.path)
        guard let url = resumeDataURL(for: record) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func register(task: URLSessionDownloadTask, in session: URLSession, record: TaskRecord) -> TaskKey {
        let key = self.key(for: session, taskID: task.taskIdentifier)
        destinations[key] = record.destination
        taskIdByDestination[record.destination.path] = key
        taskRecordByKey[key] = record
        liveTasks[key] = task
        if let expected = record.expectedSize { expectedSizes[key] = expected }
        if let offset = record.resumeOffset, offset > 0 { resumeOffsets[key] = offset }
        liveSnapshots[key] = Self.makeTaskSnapshot(
            jobID: record.jobID,
            artifactID: record.artifactID,
            destination: record.destination,
            resumeOffset: record.resumeOffset ?? 0,
            bytesReceived: max(0, task.countOfBytesReceived),
            taskExpected: task.countOfBytesExpectedToReceive > 0 ? task.countOfBytesExpectedToReceive : nil,
            recordedExpected: record.expectedSize,
            hasLiveTask: true
        )
        return key
    }

    private func refreshSessionTasks(session: URLSession, completion: (() -> Void)? = nil) {
        session.getAllTasks { [weak self] tasks in
            Task { @MainActor [weak self] in
                guard let self else {
                    completion?()
                    return
                }
                let sessionID = session.configuration.identifier ?? "foreground"
                self.liveTasks = self.liveTasks.filter { $0.key.sessionID != sessionID }
                self.liveSnapshots = self.liveSnapshots.filter { $0.key.sessionID != sessionID }
                for task in tasks {
                    guard let downloadTask = task as? URLSessionDownloadTask else { continue }
                    let key = self.key(for: session, taskID: downloadTask.taskIdentifier)
                    self.liveTasks[key] = downloadTask
                    guard let record = self.record(for: downloadTask.taskDescription) else { continue }
                    self.destinations[key] = record.destination
                    self.taskIdByDestination[record.destination.path] = key
                    self.taskRecordByKey[key] = record
                    if let expected = record.expectedSize {
                        self.expectedSizes[key] = expected
                    }
                    if let offset = record.resumeOffset, offset > 0 {
                        self.resumeOffsets[key] = offset
                    }
                    self.liveSnapshots[key] = Self.makeTaskSnapshot(
                        jobID: record.jobID,
                        artifactID: record.artifactID,
                        destination: record.destination,
                        resumeOffset: record.resumeOffset ?? 0,
                        bytesReceived: max(0, downloadTask.countOfBytesReceived),
                        taskExpected: downloadTask.countOfBytesExpectedToReceive > 0 ? downloadTask.countOfBytesExpectedToReceive : nil,
                        recordedExpected: record.expectedSize,
                        hasLiveTask: true
                    )
                }
                completion?()
            }
        }
    }

    private func lookupTask(for destination: URL, completion: @escaping (TaskKey?, URLSessionDownloadTask?) -> Void) {
        if let key = taskIdByDestination[destination.path], let task = liveTasks[key] {
            completion(key, task)
            return
        }
        refreshSessionTasks(session: backgroundSession) { [weak self] in
            guard let self else {
                completion(nil, nil)
                return
            }
            if let key = self.taskIdByDestination[destination.path], let task = self.liveTasks[key] {
                completion(key, task)
                return
            }
#if os(macOS)
            self.refreshSessionTasks(session: self.foregroundSession) { [weak self] in
                guard let self else {
                    completion(nil, nil)
                    return
                }
                if let key = self.taskIdByDestination[destination.path], let task = self.liveTasks[key] {
                    completion(key, task)
                } else {
                    completion(nil, nil)
                }
            }
#else
                completion(nil, nil)
#endif
        }
    }

    // MARK: - Public API
    /// Start a download that can continue in the background.
    @discardableResult
    func download(from remote: URL,
                  to local: URL,
                  jobID: String? = nil,
                  artifactID: String? = nil,
                  expectedSize: Int64? = nil,
                  progress: ((Double) -> Void)? = nil,
                  progressBytes: ((Int64, Int64) -> Void)? = nil) async throws -> URL {
        var req = URLRequest(url: remote)
        return try await download(
            request: req,
            to: local,
            jobID: jobID,
            artifactID: artifactID,
            expectedSize: expectedSize,
            progress: progress,
            progressBytes: progressBytes
        )
    }

    /// Start a download with a custom request (headers/auth supported).
    @discardableResult
    func download(request: URLRequest,
                  to local: URL,
                  jobID: String? = nil,
                  artifactID: String? = nil,
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

            let resumeRecord = TaskRecord(
                jobID: jobID,
                artifactID: artifactID,
                destination: local,
                expectedSize: refinedExpected,
                resumeOffset: nil,
                appendsToExistingFile: false
            )
            if let resume = self.loadResumeData(for: resumeRecord) {
                let offset = Self.extractResumeOffset(from: resume)
                let task = session.downloadTask(withResumeData: resume)
                let record = TaskRecord(
                    jobID: jobID,
                    artifactID: artifactID,
                    destination: local,
                    expectedSize: refinedExpected,
                    resumeOffset: offset > 0 ? offset : nil,
                    appendsToExistingFile: false
                )
                if let data = try? JSONEncoder().encode(record) {
                    task.taskDescription = String(data: data, encoding: .utf8)
                }
                let key = self.register(task: task, in: session, record: record)
                if let progress = progress { progressHandlers[key] = progress }
                if let progressBytes = progressBytes { progressBytesHandlers[key] = progressBytes }
                completions[key] = { cont.resume(with: $0) }
                self.clearResumeData(for: record)
                task.resume()
                return
            }

            let existingPartialBytes = self.readExistingPartialSize(at: local)
            let shouldAttemptRangeResume = existingPartialBytes > 0
            let requestToStart: URLRequest = {
                guard shouldAttemptRangeResume else { return request }
                var rangeRequest = request
                rangeRequest.setValue("bytes=\(existingPartialBytes)-", forHTTPHeaderField: "Range")
                return rangeRequest
            }()
            let task = session.downloadTask(with: requestToStart)
            let record = TaskRecord(
                jobID: jobID,
                artifactID: artifactID,
                destination: local,
                expectedSize: refinedExpected,
                resumeOffset: shouldAttemptRangeResume ? existingPartialBytes : nil,
                appendsToExistingFile: shouldAttemptRangeResume
            )
            if let data = try? JSONEncoder().encode(record) {
                task.taskDescription = String(data: data, encoding: .utf8)
            }
            let key = self.register(task: task, in: session, record: record)
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
        lookupTask(for: destination) { [weak self] key, task in
            guard let self, let key, let task else {
                completion?()
                return
            }
            let record = self.taskRecordByKey[key]
            task.cancel(byProducingResumeData: { [weak self] data in
                Task { @MainActor in
                    if let self, let data, let record {
                        self.persistResumeData(data, for: record)
                    }
                    completion?()
                }
            })
        }
    }

    func pause(destination: URL) async {
        await withCheckedContinuation { continuation in
            pause(destination: destination) {
                continuation.resume()
            }
        }
    }

    /// Cancel and discard resume data for a destination.
    func cancel(destination: URL) {
        lookupTask(for: destination) { [weak self] key, task in
            guard let self else { return }
            if let key, let record = self.taskRecordByKey[key] {
                self.clearResumeData(for: record)
            } else {
                self.resumeDataStore.removeValue(forKey: destination.path)
            }
            task?.cancel()
        }
    }

    func attachObservers(jobID: String?,
                         artifactID: String?,
                         destination: URL,
                         expectedSize: Int64? = nil,
                         progress: ((Double) -> Void)? = nil,
                         progressBytes: ((Int64, Int64) -> Void)? = nil,
                         completion: ((Result<URL, Error>) -> Void)? = nil) {
        lookupTask(for: destination) { [weak self] key, task in
            guard let self, let key else { return }
            let existingRecord = self.taskRecordByKey[key]
            let record = existingRecord ?? TaskRecord(
                jobID: jobID,
                artifactID: artifactID,
                destination: destination,
                expectedSize: expectedSize,
                resumeOffset: nil,
                appendsToExistingFile: false
            )
            if existingRecord == nil, let task {
                self.taskRecordByKey[key] = record
                self.liveTasks[key] = task
            }
            if let expectedSize, expectedSize > 0 {
                self.expectedSizes[key] = expectedSize
            }
            if let progress { self.progressHandlers[key] = progress }
            if let progressBytes { self.progressBytesHandlers[key] = progressBytes }
            if let completion { self.completions[key] = completion }
            if let snapshot = self.liveSnapshots[key] {
                if let fullExpected = snapshot.fullExpected, fullExpected > 0 {
                    let fraction = Double(snapshot.writtenTotal) / Double(fullExpected)
                    progress?(fraction)
                    progressBytes?(snapshot.writtenTotal, fullExpected)
                } else if snapshot.writtenTotal > 0 {
                    progressBytes?(snapshot.writtenTotal, 0)
                }
            }
        }
    }

    func hasLiveTask(for destination: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            lookupTask(for: destination) { _, task in
                continuation.resume(returning: task != nil)
            }
        }
    }

    func snapshot(for destination: URL) async -> BackgroundDownloadTaskSnapshot? {
        await withCheckedContinuation { continuation in
            lookupTask(for: destination) { [weak self] key, _ in
                guard let self, let key else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: self.liveSnapshots[key])
            }
        }
    }

    func snapshots() async -> [BackgroundDownloadTaskSnapshot] {
        await withCheckedContinuation { continuation in
            refreshSessionTasks(session: backgroundSession) { [weak self] in
                guard let self else {
                    continuation.resume(returning: [])
                    return
                }
#if os(macOS)
                self.refreshSessionTasks(session: self.foregroundSession) { [weak self] in
                    continuation.resume(returning: self.map { Array($0.liveSnapshots.values) } ?? [])
                }
#else
                continuation.resume(returning: Array(self.liveSnapshots.values))
#endif
            }
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
        refreshSessionTasks(session: backgroundSession) {
            NotificationCenter.default.post(name: .downloadMaintenanceRequested, object: nil)
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
        refreshSessionTasks(session: backgroundSession)
        #if os(macOS)
        refreshSessionTasks(session: foregroundSession)
        #endif
    }

    private func readExistingPartialSize(at local: URL) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: local.path),
              let size = attrs[.size] as? Int64 else {
            return 0
        }
        return max(0, size)
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
            let statusCode = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
            let storedOffset = self.resumeOffsets[key] ?? 0
            let offset = statusCode == 200 ? 0 : storedOffset
            let expectedFromTask = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
            let recordedExpected = self.expectedSizes[key]
            let normalized = Self.normalizeProgressTotals(
                resumeOffset: offset,
                totalBytesWritten: totalBytesWritten,
                taskExpected: expectedFromTask,
                recordedExpected: recordedExpected
            )
            if let record = self.taskRecordByKey[key] {
                self.liveSnapshots[key] = Self.makeTaskSnapshot(
                    jobID: record.jobID,
                    artifactID: record.artifactID,
                    destination: record.destination,
                    resumeOffset: offset,
                    bytesReceived: max(0, totalBytesWritten),
                    taskExpected: expectedFromTask,
                    recordedExpected: recordedExpected,
                    hasLiveTask: true
                )
            }

            if self.loggedProgressModes[key] != normalized.mode {
                self.loggedProgressModes[key] = normalized.mode
                let destination = self.destinations[key]?.lastPathComponent ?? "unknown"
                let taskLabel = expectedFromTask.map(String.init) ?? "nil"
                let recordedLabel = recordedExpected.map(String.init) ?? "nil"
                await logger.log(
                    "[Download][Progress] dest=\(destination) mode=\(normalized.mode.rawValue) offset=\(offset) taskExpected=\(taskLabel) recordedExpected=\(recordedLabel)"
                )
            }

            if normalized.fullExpected > 0 {
                let fraction = Double(normalized.writtenTotal) / Double(normalized.fullExpected)
                self.progressHandlers[key]?(fraction)
                self.progressBytesHandlers[key]?(normalized.writtenTotal, normalized.fullExpected)
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
            let shouldAppendRangePayload =
                record.appendsToExistingFile &&
                (downloadTask.response as? HTTPURLResponse)?.statusCode == 206 &&
                FileManager.default.fileExists(atPath: destination.path)
            if shouldAppendRangePayload {
                try Self.appendDownloadedChunk(at: location, to: destination)
                try? FileManager.default.removeItem(at: location)
            } else {
                try FileManager.default.removeItemIfExists(at: destination)
                try FileManager.default.moveItem(at: location, to: destination)
            }
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
        if let record = taskRecordByKey[key] {
            clearResumeData(for: record)
        }
        if let completion = completions[key] {
            completion(.success(destination))
        } else {
            // No in-memory continuation (likely after app restart). Notify observers so
            // they can reconcile and finalize installation from the completed file.
            let record = taskRecordByKey[key]
            NotificationCenter.default.post(
                name: .backgroundDownloadCompleted,
                object: nil,
                userInfo: [
                    "destinationURL": destination,
                    "taskID": key.taskID,
                    "jobID": record?.jobID as Any,
                    "artifactID": record?.artifactID as Any
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
            if let task = liveTasks[key], let url = task.originalRequest?.url {
                info["originalURL"] = url
            }
            if let dest = destinations[key] { info["destinationURL"] = dest }
            if let record = taskRecordByKey[key] {
                info["jobID"] = record.jobID
                info["artifactID"] = record.artifactID
            }
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
        taskRecordByKey[key] = nil
        liveTasks[key] = nil
        progressThrottler.clear(key: key)
        completions[key] = nil
        progressHandlers[key] = nil
        progressBytesHandlers[key] = nil
        expectedSizes[key] = nil
        resumeOffsets[key] = nil
        liveSnapshots[key] = nil
        loggedProgressModes[key] = nil
    }
}

extension BackgroundDownloadManager {
    nonisolated private static func appendDownloadedChunk(at chunkURL: URL, to destination: URL) throws {
        let chunkHandle = try FileHandle(forReadingFrom: chunkURL)
        defer { try? chunkHandle.close() }
        let destinationHandle = try FileHandle(forWritingTo: destination)
        defer { try? destinationHandle.close() }
        try destinationHandle.seekToEnd()
        while autoreleasepool(invoking: {
            let data = try? chunkHandle.read(upToCount: 1_048_576) ?? Data()
            guard let data, !data.isEmpty else { return false }
            try? destinationHandle.write(contentsOf: data)
            return true
        }) {}
    }

    nonisolated static func makeTaskSnapshot(jobID: String?,
                                             artifactID: String?,
                                             destination: URL,
                                             resumeOffset: Int64,
                                             bytesReceived: Int64,
                                             taskExpected: Int64?,
                                             recordedExpected: Int64?,
                                             hasLiveTask: Bool) -> BackgroundDownloadTaskSnapshot {
        let normalized = normalizeProgressTotals(
            resumeOffset: resumeOffset,
            totalBytesWritten: max(0, bytesReceived),
            taskExpected: taskExpected,
            recordedExpected: recordedExpected
        )
        return BackgroundDownloadTaskSnapshot(
            jobID: jobID,
            artifactID: artifactID,
            destination: destination,
            resumeOffset: max(0, resumeOffset),
            bytesReceived: max(0, bytesReceived),
            taskExpectedBytes: taskExpected,
            recordedExpectedBytes: recordedExpected,
            writtenTotal: normalized.writtenTotal,
            fullExpected: normalized.fullExpected > 0 ? normalized.fullExpected : nil,
            hasLiveTask: hasLiveTask
        )
    }

    nonisolated static func normalizeProgressTotals(
        resumeOffset: Int64,
        totalBytesWritten: Int64,
        taskExpected: Int64?,
        recordedExpected: Int64?
    ) -> DownloadProgressNormalizationResult {
        let offset = max(0, resumeOffset)
        let writtenTotal = totalBytesWritten + offset
        let expectedFromTask = taskExpected.flatMap { $0 > 0 ? $0 : nil }
        let expectedFromRecord = recordedExpected.flatMap { $0 > 0 ? $0 : nil }

        if offset == 0 {
            if let expectedFromTask {
                return DownloadProgressNormalizationResult(
                    writtenTotal: totalBytesWritten,
                    fullExpected: expectedFromTask,
                    mode: .freshTask
                )
            }
            if let expectedFromRecord {
                return DownloadProgressNormalizationResult(
                    writtenTotal: totalBytesWritten,
                    fullExpected: expectedFromRecord,
                    mode: .freshRecorded
                )
            }
            return DownloadProgressNormalizationResult(
                writtenTotal: totalBytesWritten,
                fullExpected: -1,
                mode: .unknown
            )
        }

        if let expectedFromTask {
            if let expectedFromRecord {
                let tolerance = max(Int64(512 * 1024), expectedFromRecord / 100)
                if abs(expectedFromTask - expectedFromRecord) <= tolerance {
                    return DownloadProgressNormalizationResult(
                        writtenTotal: writtenTotal,
                        fullExpected: expectedFromRecord,
                        mode: .resumeFullSize
                    )
                }

                let remainingExpected = offset + expectedFromTask
                if expectedFromTask + tolerance < expectedFromRecord {
                    return DownloadProgressNormalizationResult(
                        writtenTotal: writtenTotal,
                        fullExpected: remainingExpected,
                        mode: .resumeRemainingBytes
                    )
                }

                return DownloadProgressNormalizationResult(
                    writtenTotal: writtenTotal,
                    fullExpected: max(expectedFromRecord, remainingExpected),
                    mode: .resumeFallback
                )
            }

            return DownloadProgressNormalizationResult(
                writtenTotal: writtenTotal,
                fullExpected: offset + expectedFromTask,
                mode: .resumeNoRecorded
            )
        }

        if let expectedFromRecord {
            return DownloadProgressNormalizationResult(
                writtenTotal: writtenTotal,
                fullExpected: expectedFromRecord,
                mode: .resumeRecordedOnly
            )
        }

        return DownloadProgressNormalizationResult(
            writtenTotal: writtenTotal,
            fullExpected: -1,
            mode: .unknown
        )
    }

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
        // iOS/iPadOS: durable downloads always use the background session so they
        // survive suspend/lock and can be reattached after relaunch.
        let state = UIApplication.sharedIfAvailable?.applicationState
        let stateLabel: String = {
            switch state {
            case .some(.active): return "active"
            case .some(.background): return "background"
            case .some(.inactive): return "inactive"
            default: return "unknown"
            }
        }()
        logSessionChoice(kind: .background, reason: "durable iOS transfer appState=\(stateLabel)")
        return backgroundSession
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
private extension UIApplication {
    static var sharedIfAvailable: UIApplication? {
        // Avoid accessing UIApplication in app extensions
        guard NSClassFromString("UIApplication") != nil else { return nil }
        return UIApplication.perform(NSSelectorFromString("sharedApplication"))?.takeUnretainedValue() as? UIApplication
    }
}
#endif

// FileManager helper is defined globally in Noema.swift
