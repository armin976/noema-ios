import Foundation

public enum AppDataPathResolver {
    public static func resolve(path: String, allowedRoots: [URL], fileManager: FileManager = .default) throws -> URL {
        let trimmedPath: String
        if path.hasPrefix("/") {
            trimmedPath = String(path.dropFirst())
        } else {
            trimmedPath = path
        }
        let components = trimmedPath.split(separator: "/")
        if components.contains("..") {
            throw AppError(code: .pathDenied, message: "Path traversal blocked for \(path)")
        }
        for root in allowedRoots {
            if trimmedPath.isEmpty {
                return root.standardizedFileURL.resolvingSymlinksInPath()
            }
            let candidate = root.appendingPathComponent(trimmedPath)
            let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()
            let normalizedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
            if resolved.path == normalizedRoot.path || resolved.path.hasPrefix(normalizedRoot.path + "/") {
                return resolved
            }
        }
        throw AppError(code: .pathDenied, message: "Path \(path) denied")
    }
}
