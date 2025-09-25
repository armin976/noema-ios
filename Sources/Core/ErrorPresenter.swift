import Foundation

public enum AppErrorCode: String, Codable, Sendable {
    case pyTimeout
    case pyExec
    case pyMemory
    case cacheCorrupt
    case cacheMiss
    case exportFailed
    case pathDenied
    case crewBudget
    case unknown
}

public struct AppError: LocalizedError, Codable, Sendable {
    public let code: AppErrorCode
    public let message: String
    public let suggestion: String?

    public init(code: AppErrorCode, message: String, suggestion: String? = nil) {
        self.code = code
        self.message = message
        self.suggestion = suggestion
    }

    public var errorDescription: String? {
        "[\(code.rawValue)] \(message)"
    }
}

public enum ErrorPresenter {
    public static func present(_ error: AppError) -> String {
        switch error.code {
        case .pyTimeout:
            return "Python timed out. Try smaller samples or increase timeout."
        case .pyMemory:
            return "Python ran out of memory. Sample with nrows=… or drop columns."
        case .cacheCorrupt:
            return "Cached artifacts are invalid. Clear cache and rerun."
        case .pathDenied:
            return "Access to that path is not allowed."
        case .exportFailed:
            return "Could not create export archive."
        case .crewBudget:
            return "Crew stopped at budget limit."
        default:
            return error.message
        }
    }
}
