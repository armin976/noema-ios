import Foundation

public struct ExportManifest: Codable, Equatable, Sendable {
    public struct AppInfo: Codable, Equatable, Sendable {
        public var appVersion: String
        public var osVersion: String

        public init(appVersion: String, osVersion: String) {
            self.appVersion = appVersion
            self.osVersion = osVersion
        }
    }

    public struct ToolInfo: Codable, Equatable, Sendable {
        public var name: String
        public var version: String

        public init(name: String, version: String) {
            self.name = name
            self.version = version
        }
    }

    public struct DatasetRef: Codable, Equatable, Sendable {
        public var name: String
        public var path: String
        public var sha256: String?
        public var size: Int64?

        public init(name: String, path: String, sha256: String? = nil, size: Int64? = nil) {
            self.name = name
            self.path = path
            self.sha256 = sha256
            self.size = size
        }
    }

    public struct CacheRef: Codable, Equatable, Sendable {
        public var key: String
        public var files: [String]
        public var sha256: [String: String]

        public init(key: String, files: [String], sha256: [String: String]) {
            self.key = key
            self.files = files
            self.sha256 = sha256
        }
    }

    public var createdAt: String
    public var app: AppInfo
    public var tools: [ToolInfo]
    public var notebookFile: String
    public var notebookMetaFile: String?
    public var datasets: [DatasetRef]
    public var caches: [CacheRef]
    public var warnings: [String]

    public init(createdAt: String,
                app: AppInfo,
                tools: [ToolInfo],
                notebookFile: String,
                notebookMetaFile: String? = nil,
                datasets: [DatasetRef] = [],
                caches: [CacheRef] = [],
                warnings: [String] = []) {
        self.createdAt = createdAt
        self.app = app
        self.tools = tools
        self.notebookFile = notebookFile
        self.notebookMetaFile = notebookMetaFile
        self.datasets = datasets
        self.caches = caches
        self.warnings = warnings
    }
}
