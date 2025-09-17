// Logger.swift
import Foundation

/// Simple async logger used to capture text messages in a file.
/// Declared as an actor so calls from various tasks remain concurrency-safe.
actor Logger {
    /// Singleton instance used throughout the app.
    static let shared = Logger()

    /// URL of the log file on disk. Accessed from UI so marked nonisolated.
    nonisolated let logFileURL: URL

    private var handle: FileHandle?

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("noema.log")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        logFileURL = url
        handle = try? FileHandle(forWritingTo: url)
        handle?.seekToEndOfFile()
    }

    /// Appends a line of text to the log file.
    func log(_ message: String) {
        if let data = (message + "\n").data(using: .utf8) {
            handle?.write(data)
        }
        // Prevent flooding the Xcode console with extremely long lines.
        // Print a truncated preview but always write the full message to the file above.
        let maxConsoleChars = 10000
        if message.count > maxConsoleChars {
            let preview = message.prefix(maxConsoleChars)
            print(String(preview) + "… [truncated, len=\(message.count)]")
        } else {
            print(message)
        }
    }
}

/// Convenience global constant for ease of use.
let logger = Logger.shared
