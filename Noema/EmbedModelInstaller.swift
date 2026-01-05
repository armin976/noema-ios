// EmbedModelInstaller.swift
import Foundation
import SwiftUI

@MainActor
final class EmbedModelInstaller: ObservableObject {
    enum State: Equatable {
        case idle
        case downloading
        case verifying
        case installing
        case ready
        case failed(String)
    }

    @Published var progress: Double = 0
    @Published var state: State = .idle

    // Updated to the stable v1.5 embedding model recommended in RAG_FIX_INSTRUCTIONS.md
    private let remoteURL = URL(string: "https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF/resolve/main/nomic-embed-text-v1.5.Q4_K_M.gguf?download=1")!

    init() {
        refreshStateFromDisk()
    }

    func installIfNeeded() async {
        progress = 0
        state = .idle
        if FileManager.default.fileExists(atPath: EmbeddingModel.modelURL.path) {
            state = .ready
            progress = 1
            notifyAvailabilityChanged(true)
            return
        }
        state = .downloading
        do {
            // Ensure destination directory exists first
            try FileManager.default.createDirectory(at: EmbeddingModel.modelDir, withIntermediateDirectories: true)
            let dest = EmbeddingModel.modelURL
            try await BackgroundDownloadManager.shared.download(from: remoteURL, to: dest, expectedSize: nil) { [weak self] p in
                // Progress callback may be non-async; hop to main safely.
                Task { @MainActor in self?.progress = p }
            }
            state = .verifying
            try verifyGGUF(at: dest)
            state = .installing
            // File is already at destination, nothing to move
            // Log the successful download + install so we can trace this in the console / log file.
            Task.detached { await logger.log("[EmbedInstaller] ✅ Embedding model downloaded and installed at: \(EmbeddingModel.modelURL.path)") }
            UserDefaults.standard.set(true, forKey: "hasInstalledEmbedModel:\(EmbeddingModel.modelURL.path)")
            state = .ready
            progress = 1
            notifyAvailabilityChanged(true)
        } catch {
            state = .failed(error.localizedDescription)
            notifyAvailabilityChanged(false)
        }
    }

    /// Refresh the installer state based on whether the model file exists on disk.
    /// This does not initiate any downloads; it purely reflects current disk state.
    func refreshStateFromDisk() {
        if FileManager.default.fileExists(atPath: EmbeddingModel.modelURL.path) {
            state = .ready
            progress = 1
            notifyAvailabilityChanged(true)
        } else {
            state = .idle
            progress = 0
            notifyAvailabilityChanged(false)
        }
    }

    private func verifyGGUF(at url: URL) throws {
        let fh = try FileHandle(forReadingFrom: url)
        defer { try? fh.close() }
        let magic = try fh.read(upToCount: 4) ?? Data()
        guard magic.count == 4, let s = String(data: magic, encoding: .ascii), s == "GGUF" else {
            throw NSError(domain: "Noema", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid GGUF header"])
        }
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attrs[.size] as? NSNumber, size.intValue < 1_000_000 {
            throw NSError(domain: "Noema", code: 3, userInfo: [NSLocalizedDescriptionKey: "File too small"])
        }
    }

    private func atomicMove(from: URL, to: URL) throws {
        try FileManager.default.createDirectory(at: EmbeddingModel.modelDir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: to.path) {
            try FileManager.default.removeItem(at: to)
        }
        try FileManager.default.moveItem(at: from, to: to)
    }

    private func notifyAvailabilityChanged(_ available: Bool) {
        NotificationCenter.default.post(name: .embeddingModelAvailabilityChanged, object: nil, userInfo: ["available": available])
    }
}
