import Foundation

public struct PyRunKey: Hashable, Codable, Sendable {
    public let codeHash: String
    public let filesHash: String
    public let runnerVersion: String

    public init(code: String, files: [PythonMountFile], runnerVersion: String) {
        self.codeHash = PyRunKey.hashString(for: Data(code.utf8))
        self.filesHash = PyRunKey.hashFiles(files)
        self.runnerVersion = runnerVersion
    }

    public init(codeHash: String, filesHash: String, runnerVersion: String) {
        self.codeHash = codeHash
        self.filesHash = filesHash
        self.runnerVersion = runnerVersion
    }

    private static func hashFiles(_ files: [PythonMountFile]) -> String {
        guard !files.isEmpty else { return hashString(for: Data()) }
        var hasher = SHA256Hasher()
        for file in files.sorted(by: { $0.name < $1.name }) {
            hasher.update(data: file.data)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func hashString(for data: Data) -> String {
        var hasher = SHA256Hasher()
        hasher.update(data: data)
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public var identifier: String {
        [codeHash, filesHash, runnerVersion].joined(separator: "-")
    }
}
