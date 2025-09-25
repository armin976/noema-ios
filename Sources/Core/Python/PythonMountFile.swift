import Foundation

public struct PythonMountFile: Hashable, Codable, Sendable {
    public let name: String
    public let data: Data
    public let url: URL

    public init(url: URL, data: Data) {
        self.url = url
        self.name = url.lastPathComponent
        self.data = data
    }

    public init(name: String, data: Data, url: URL) {
        self.name = name
        self.data = data
        self.url = url
    }
}
