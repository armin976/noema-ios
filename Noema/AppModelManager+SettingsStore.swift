// AppModelManager+SettingsStore.swift
import Foundation

/// Durable per-model settings persistence using Keychain with a local JSON mirror.
/// This survives app reinstalls (via Keychain) and also maintains a readable file for diagnostics.
enum ModelSettingsStore {
    private static let service = "Noema.ModelSettings"
    private static let account = "perModel.v1"

    private struct Entry: Codable {
        let modelID: String
        let quantLabel: String
        let settings: ModelSettings
    }

    private struct Payload: Codable {
        var entries: [Entry]
    }

    private static func mirrorURL() -> URL? {
        // Store a human-readable mirror under Documents/ModelSettings/model_settings.json
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return docs?
            .appendingPathComponent("ModelSettings", isDirectory: true)
            .appendingPathComponent("model_settings.json")
    }

    /// Loads settings map keyed by (modelID, quantLabel)
    static func load() -> [String: ModelSettings] {
        func toKey(_ id: String, _ quant: String) -> String { id + "|" + quant }
        // Try Keychain first
        if let data = try? KeychainStore.read(service: service, account: account) {
            if let payload = try? JSONDecoder().decode(Payload.self, from: data) {
                var out: [String: ModelSettings] = [:]
                for e in payload.entries { out[toKey(e.modelID, e.quantLabel)] = e.settings }
                return out
            }
        }
        // Fallback to mirror file
        if let url = mirrorURL(), let data = try? Data(contentsOf: url) {
            if let payload = try? JSONDecoder().decode(Payload.self, from: data) {
                var out: [String: ModelSettings] = [:]
                for e in payload.entries { out[toKey(e.modelID, e.quantLabel)] = e.settings }
                return out
            }
        }
        return [:]
    }

    /// Saves settings map keyed by (modelID|quantLabel) back to Keychain and the mirror file.
    static func save(_ map: [String: ModelSettings]) {
        // Convert back to payload
        let entries: [Entry] = map.compactMap { (k, v) in
            guard let sep = k.firstIndex(of: "|") else { return nil }
            let id = String(k[..<sep])
            let quant = String(k[k.index(after: sep)...])
            return Entry(modelID: id, quantLabel: quant, settings: v)
        }
        let payload = Payload(entries: entries)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        // Write Keychain
        do { try KeychainStore.write(service: service, account: account, data: data) } catch { /* ignore */ }
        // Write mirror
        if let url = mirrorURL() {
            let fm = FileManager.default
            do {
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: [.atomic])
            } catch { /* ignore */ }
        }
    }

    /// Updates a single model entry in persistent storage (Keychain + mirror).
    static func save(settings: ModelSettings, forModelID modelID: String, quantLabel: String) {
        var current = load()
        current[modelID + "|" + quantLabel] = settings
        save(current)
    }
}

