// DomainModels.swift
import Foundation
import SwiftUI

public enum ModelFormat: String, Codable, CaseIterable, Hashable, Sendable {
    case gguf = "GGUF"
    case mlx = "MLX"
    case slm  = "SLM"
    case apple = "APPLE"
}

extension ModelFormat {
    var tagGradient: LinearGradient {
        switch self {
        case .mlx:
            return LinearGradient(colors: [Color.orange, Color.pink], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .gguf:
            return LinearGradient(colors: [Color.blue, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .slm:
            return LinearGradient(colors: [Color.cyan, Color.blue], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .apple:
            return LinearGradient(colors: [Color.green, Color.teal], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    /// Attempts to infer the format from a model file URL.
    /// Unknown extensions default to GGUF for backwards compatibility with GGML.
    static func detect(from url: URL) -> ModelFormat {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "mlx":
            return .mlx
        case "bundle":
            return .slm
        case "gguf", "ggml", "bin":
            return .gguf
        default:
            return .gguf
        }
    }
}

public struct QuantInfo: Identifiable, Hashable, Codable, Sendable {
    public var id: String { label }
    public let label: String
    public let format: ModelFormat
    public let sizeBytes: Int64
    public let downloadURL: URL
    public let sha256: String?
    /// Optional URL to a configuration JSON accompanying the model
    public let configURL: URL?
}

extension QuantInfo {
    /// Attempts to infer the quantization bit-width from the label (e.g. Q4_K_M → 4, "MLX 4bit" → 4).
    var inferredBitWidth: Int? {
        if let range = label.range(of: #"(\d{1,2})(?:\s*bit)?"#, options: .regularExpression) {
            let digits = label[range].replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
            if let value = Int(digits) {
                return value
            }
        }
        return nil
    }

    /// Returns true when the quant is at least Q3 (or equivalent, e.g. IQ4, 4bit, FP16).
    var isHighBitQuant: Bool {
        if let bits = inferredBitWidth {
            return bits >= 3
        }

        let lowered = label.lowercased()
        // If we could not infer bit-width, fall back to catching explicit low-bit tokens.
        let disallowedTokens = ["q1", "q2", "iq1", "iq2"]
        return !disallowedTokens.contains { lowered.contains($0) }
    }
}

public struct ModelRecord: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let displayName: String
    public let publisher: String
    /// One line summary shown in lists and detail headers
    public let summary: String?
    public let hasInstallableQuant: Bool
    public let formats: Set<ModelFormat>
    public let installed: Bool
    public let tags: [String]?
    public let pipeline_tag: String?
}

public struct ModelDetails: Identifiable, Hashable, Codable, Equatable, Sendable {
    public let id: String
    /// Canonical one line summary for the model
    public let summary: String?
    public let quants: [QuantInfo]
    public let promptTemplate: String?
}

extension ModelDetails {
    /// Returns true if this model is vision-capable according to cached Hub metadata
    /// or local GGUF heuristics (first available GGUF quant).
    var isVision: Bool {
        // Prefer Hub pipeline_tag/tags
        if let meta = HuggingFaceMetadataCache.cached(repoId: id), meta.isVision {
            return true
        }
        // Fallback: if there is a GGUF quant, try to heuristically detect vision
        if let gguf = quants.first(where: { $0.format == .gguf }) {
            let dir = InstalledModelsStore.baseDir(for: .gguf, modelID: id)
            // If already downloaded, check the gguf header for indicators
            if let local = InstalledModelsStore.firstGGUF(in: dir) {
                if ChatVM.guessLlamaVisionModel(from: local) { return true }
                if GGUFMetadata.isVisionLikely(at: local) { return true }
            }
            // If not present locally yet, heuristically infer from repo id
            if VisionModelDetector.isVisionModelCachedOrHeuristic(repoId: id) { return true }
            // As a last resort, try to infer from the download filename (cheap heuristic)
            let lower = gguf.downloadURL.lastPathComponent.lowercased()
            if lower.contains("vl") || lower.contains("vision") || lower.contains("llava") { return true }
        }
        return false
    }
}

enum ModelSource: String, Codable, CaseIterable, Hashable, Sendable {
    case huggingFace = "HF"
    case leap = "LEAP"
}

/// Common metadata for any downloadable model entry.
protocol DownloadableModel: Identifiable {
    var id: String { get }
    var name: String { get }
    var sizeMB: Double { get }
    var minRAM: Int { get }
    var remoteURL: URL { get }
    var localPath: URL? { get }
    var about: String? { get }
    var format: ModelFormat { get }
    var source: ModelSource { get }
}

struct LeapModel: DownloadableModel, Codable, Sendable {
    let id: String
    let name: String
    let sizeMB: Double
    let minRAM: Int
    let remoteURL: URL
    var localPath: URL?
    let about: String?
    let format: ModelFormat = .slm
    let source: ModelSource = .leap
}

extension QuantInfo: DownloadableModel {
    var name: String { label }
    var sizeMB: Double { Double(sizeBytes) / 1_048_576.0 }
    var minRAM: Int { 0 }
    var remoteURL: URL { downloadURL }
    var localPath: URL? { nil }
    var about: String? { nil }
    var source: ModelSource { .huggingFace }
}

// MARK: - Dataset support

/// Lightweight metadata used when listing available datasets.
public struct DatasetRecord: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let displayName: String
    public let publisher: String
    public let summary: String?
    public let installed: Bool
}

/// Represents a file that belongs to a dataset.
public struct DatasetFile: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public let sizeBytes: Int64
    public let downloadURL: URL
}

/// Detailed metadata about a dataset including its file list.
public struct DatasetDetails: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let summary: String?
    public let files: [DatasetFile]
    /// Optional human-readable display name (e.g., OTL title). When present, it will be persisted alongside the dataset.
    public let displayName: String?
}

/// Installed dataset stored on disk.
struct LocalDataset: Identifiable, Hashable {
    // Use stable identifier derived from datasetID to prevent List re-creation and scroll jumps
    var id: String { datasetID }
    let datasetID: String
    let name: String
    let url: URL
    /// Size of the dataset in megabytes.
    let sizeMB: Double
    let source: String
    let downloadDate: Date
    var lastUsedDate: Date?
    var isSelected: Bool = false
    var isIndexed: Bool = false
}

// MARK: - Dataset processing / indexing status (UI + pipeline)

/// Stages for dataset preparation and embedding.
public enum DatasetProcessingStage: String, Codable, Sendable {
    case extracting
    case compressing
    case embedding
    case completed
    case failed
}

/// Progress payload published while preparing a dataset.
public struct DatasetProcessingStatus: Codable, Sendable {
    public let stage: DatasetProcessingStage
    /// 0.0 ... 1.0 where 1.0 means finished for the current stage
    public let progress: Double
    /// Optional human-readable status string for the UI
    public let message: String?
    /// Estimated seconds remaining for the current stage (if available)
    public let etaSeconds: Double?

    public init(stage: DatasetProcessingStage, progress: Double, message: String? = nil, etaSeconds: Double? = nil) {
        self.stage = stage
        self.progress = progress
        self.message = message
        self.etaSeconds = etaSeconds
    }
}
