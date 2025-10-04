// AppSecrets.swift
import Foundation

/// Centralizes access to secrets that are supplied via `Secrets.plist`
/// (kept locally and ignored by git) or environment variables when running
/// from the command line.
enum AppSecrets {
    enum Key: String {
        case searxngURL = "SearXNGURL"
    }

    private static let secrets: [String: String]? = {
        guard let url = locateSecretsFile(),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: PropertyListSerialization.ReadOptions(), format: nil) as? [String: String] else {
            return nil
        }
        return plist
    }()

    private static func locateSecretsFile() -> URL? {
        let candidateBundles: [Bundle] = [Bundle.main] + Bundle.allBundles + Bundle.allFrameworks
        for bundle in candidateBundles {
            if let url = bundle.url(forResource: "Secrets", withExtension: "plist") {
                return url
            }
        }
        return nil
    }

    private static func environmentOverride(for key: Key) -> String? {
        let env = ProcessInfo.processInfo.environment
        switch key {
        case .searxngURL:
            return env["SEARXNG_URL"]
        }
    }

    private static func trimmedValue(_ string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func string(for key: Key) -> String? {
        if let override = environmentOverride(for: key), let trimmed = trimmedValue(override) {
            return trimmed
        }
        guard let stored = secrets?[key.rawValue] else {
            return nil
        }
        return trimmedValue(stored)
    }

    static func requireString(for key: Key) -> String {
        guard let value = string(for: key) else {
            fatalError("Missing secret for key \(key.rawValue). Provide it in Secrets.plist or via environment variables.")
        }
        return value
    }

    static func url(for key: Key) -> URL? {
        guard let urlString = string(for: key) else { return nil }
        return URL(string: urlString)
    }

    static func requireURL(for key: Key) -> URL {
        guard let url = url(for: key) else {
            fatalError("Missing or invalid URL for key \(key.rawValue). Provide a valid entry in Secrets.plist or via environment variables.")
        }
        return url
    }

    private static var defaultSearXNGURL: URL {
        URL(string: "https://search.noemaai.com/search")!
    }

    static var searxngSearchURL: URL {
        url(for: .searxngURL) ?? defaultSearXNGURL
    }

    static var optionalSearXNGURL: URL? {
        url(for: .searxngURL)
    }
}
