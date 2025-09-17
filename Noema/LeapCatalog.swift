// LeapCatalog.swift
import Foundation

struct LeapCatalogEntry: Identifiable, Codable, Hashable {
    var id: String { slug }
    /// Canonical model slug
    let slug: String
    /// Human friendly display name
    let displayName: String
    /// Uncompressed bundle size in bytes
    let sizeBytes: Int64
    /// Optional checksum for integrity verification
    let sha256: String?
}
