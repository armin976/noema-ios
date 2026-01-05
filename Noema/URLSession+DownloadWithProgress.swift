// URLSession+DownloadWithProgress.swift
import Foundation

extension URLSession {
        /// Async wrapper around `download` that reports progress via a closure.
        /// - Parameters:
        ///   - url: Remote URL to download from.
        ///   - expectedSize: When known ahead of time, pass the expected byte count so progress
        ///     can be computed without needing a HEAD request.
        ///   - progress: Closure periodically called with `(fractionComplete, bytesWritten)`.
        func downloadWithProgress(
                from url: URL,
                expectedSize: Int64? = nil,
                progress: @escaping @Sendable (Double, Int64) async -> Void
        ) async throws -> (URL, URLResponse) {
                if NetworkKillSwitch.isEnabled { throw URLError(.notConnectedToInternet) }
                final class Handler: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
                        let progressHandler: @Sendable (Double, Int64) async -> Void
                        let knownExpected: Int64
                        var lastBytes: Int64 = 0
                        /// Rolling estimate for downloads where the server does not report size.
                        var estimatedSize: Int64 = 8 * 1024 * 1024 // start with 8MB

                        init(knownExpected: Int64, progress: @escaping @Sendable (Double, Int64) async -> Void) {
                                self.knownExpected = knownExpected
                                self.progressHandler = progress
                        }

                        func urlSession(
                                _ session: URLSession,
                                downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64,
                                totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64
                        ) {
                                lastBytes = totalBytesWritten
                                let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : (knownExpected > 0 ? knownExpected : -1)
                                if expected > 0 {
                                        let fraction = Double(totalBytesWritten) / Double(expected)
                                        Task { await progressHandler(fraction, totalBytesWritten) }
                                } else {
                                        // No expected size available; grow a rolling estimate so progress still updates.
                                        if totalBytesWritten > estimatedSize { estimatedSize = totalBytesWritten * 2 }
                                        let estimatedFraction = min(0.95, Double(totalBytesWritten) / Double(estimatedSize))
                                        Task { await progressHandler(estimatedFraction, totalBytesWritten) }
                                }
                        }
                        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
                }

                // Use provided expected size when available, otherwise attempt discovery via HEAD/Range.
                var knownExpected: Int64 = expectedSize ?? 0
                if knownExpected <= 0 {
                        do {
                                var head = URLRequest(url: url)
                                head.httpMethod = "HEAD"
                                head.setValue("bytes=0-0", forHTTPHeaderField: "Range")
                                head.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                                let (_, resp) = try await self.data(for: head)
                                if let http = resp as? HTTPURLResponse {
                                        if let range = http.value(forHTTPHeaderField: "Content-Range"),
                                           let totalStr = range.split(separator: "/").last,
                                           let total = Int64(totalStr) {
                                                knownExpected = total
                                        } else if let lenStr = http.value(forHTTPHeaderField: "Content-Length"),
                                                      let len = Int64(lenStr) {
                                                knownExpected = len
                                        }
                                }
                        } catch {
                                // Ignore; we will still emit final 100% at the end
                        }
                }

                let delegate = Handler(knownExpected: knownExpected, progress: progress)
                let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
                NetworkKillSwitch.track(session: session)
                defer { session.finishTasksAndInvalidate() }
                let result = try await session.download(from: url)
                await progress(1, delegate.lastBytes)
                return result
        }
}
