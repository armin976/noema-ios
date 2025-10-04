import Foundation
import UIKit

#if canImport(BackgroundTasks) && !os(visionOS)
import BackgroundTasks
#endif

/// Manages large downloads that should continue while the app is suspended or terminated.
/// Uses a background URLSession with a fixed identifier and exposes a simple async API.
final class BackgroundDownloadManager: NSObject {
    static let shared = BackgroundDownloadManager()

    private struct TaskRecord: Codable {
        let destination: URL
        let expectedSize: Int64?
    }

    private let sessionIdentifier = "com.noema.background-download"
    #if canImport(BackgroundTasks) && !os(visionOS)
    private let maintenanceTaskIdentifier = "com.noema.download.maintenance"
    #endif

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
        config.sessionSendsLaunchEvents = true
        config.waitsForConnectivity = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private var destinations: [Int: URL] = [:]
    private var completions: [Int: (Result<URL, Error>) -> Void] = [:]
    private var progressHandlers: [Int: (Double) -> Void] = [:]
    private var expectedSizes: [Int: Int64] = [:]
    private var backgroundCompletionHandler: (() -> Void)?

    private override init() {
        super.init()
        #if canImport(BackgroundTasks) && !os(visionOS)
        registerBackgroundTask()
        #endif
        restorePersistedTasks()
    }

    // MARK: - Public API
    /// Start a download that can continue in the background.
    @discardableResult
    func download(from remote: URL,
                  to local: URL,
                  expectedSize: Int64? = nil,
                  progress: ((Double) -> Void)? = nil) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            let task = session.downloadTask(with: remote)
            let record = TaskRecord(destination: local, expectedSize: expectedSize)
            if let data = try? JSONEncoder().encode(record) {
                task.taskDescription = String(data: data, encoding: .utf8)
            }
            destinations[task.taskIdentifier] = record.destination
            if let expected = record.expectedSize { expectedSizes[task.taskIdentifier] = expected }
            if let progress = progress { progressHandlers[task.taskIdentifier] = progress }
            completions[task.taskIdentifier] = { cont.resume(with: $0) }
            task.resume()
        }
    }

    /// Called from AppDelegate when the system wakes us for background events.
    func handleEvents(for identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == sessionIdentifier else { completionHandler(); return }
        _ = session // ensure the session is instantiated so the system can deliver events
        restorePersistedTasks()
        backgroundCompletionHandler = completionHandler
    }

    // MARK: - BGTaskScheduler
    #if canImport(BackgroundTasks) && !os(visionOS)
    private func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: maintenanceTaskIdentifier, using: nil) { task in
            self.handleMaintenance(task: task as! BGProcessingTask)
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
        session.getAllTasks { _ in
            // Reconcile stalled tasks or perform cleanup as needed.
            task.setTaskCompleted(success: true)
        }
    }
    #else
    func scheduleMaintenance() {
        // BGProcessingTask isn't supported on visionOS. Downloads still work
        // while the scene is active thanks to the background URLSession.
    }
    #endif

    private func restorePersistedTasks() {
        session.getAllTasks { tasks in
            for task in tasks {
                guard let record = self.record(for: task) else { continue }
                self.destinations[task.taskIdentifier] = record.destination
                if let expected = record.expectedSize {
                    self.expectedSizes[task.taskIdentifier] = expected
                }
            }
        }
    }

    private func record(for task: URLSessionTask) -> TaskRecord? {
        guard let desc = task.taskDescription,
              let data = desc.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TaskRecord.self, from: data)
    }
}

// MARK: - URLSessionDownloadDelegate
extension BackgroundDownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedSizes[downloadTask.taskIdentifier] ?? -1
        if expected > 0 {
            let fraction = Double(totalBytesWritten) / Double(expected)
            progressHandlers[downloadTask.taskIdentifier]?(fraction)
        }
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let id = downloadTask.taskIdentifier
        defer { cleanup(taskId: id) }
        let dest = destinations[id] ?? record(for: downloadTask)?.destination
        guard let dest else {
            completions[id]?(.failure(URLError(.unknown)))
            return
        }
        do {
            try FileManager.default.removeItemIfExists(at: dest)
            try FileManager.default.moveItem(at: location, to: dest)
            completions[id]?(.success(dest))
        } catch {
            completions[id]?(.failure(error))
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard let error = error else { return }
        let id = task.taskIdentifier
        completions[id]?(.failure(error))
        cleanup(taskId: id)
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        backgroundCompletionHandler?()
        backgroundCompletionHandler = nil
    }

    private func cleanup(taskId: Int) {
        destinations[taskId] = nil
        completions[taskId] = nil
        progressHandlers[taskId] = nil
        expectedSizes[taskId] = nil
    }
}

// FileManager helper is defined globally in Noema.swift
