// LeapCatalog.swift
import Foundation

struct LeapCatalogEntry: Identifiable, Codable, Hashable {
    var id: String { slug }
    enum ArtifactKind: String, Codable {
        case bundle
        case manifest
    }
    /// Stable unique key used for row identity and download bookkeeping.
    let slug: String
    /// Logical model id (without quantization token when possible).
    let modelID: String
    /// Quantization token shown in Explore (e.g. Q8_0, 8da4w).
    let quantization: String
    /// Human-friendly display name.
    let displayName: String
    /// Reported size in bytes (for manifests this may be 0 until resolved at download time).
    let sizeBytes: Int64
    /// Optional checksum for integrity verification.
    let sha256: String?
    /// Remote path under LiquidAI/LeapBundles siblings list.
    let remotePath: String
    /// Whether this entry points to a bundled artifact or a GGUF manifest.
    let artifactKind: ArtifactKind
    /// Lightweight modality signal used by Explore filters and metadata defaults.
    let isVision: Bool
}

extension LeapCatalogEntry {
    var sourceFormatLabel: String {
        switch artifactKind {
        case .bundle:
            return "EXECUTORCH"
        case .manifest:
            return "GGUF"
        }
    }
}
