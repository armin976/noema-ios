// QuantExtractor.swift
import Foundation

public struct RepoFile { let path: String; let size: Int64; let sha256: String? }

public enum QuantExtractor {
    static func extract(from files: [RepoFile], repoID: String) -> [QuantInfo] {
        var quants: [QuantInfo] = []
        var seenLabels: Set<String> = []
        for file in files {
            let lower = file.path.lowercased()
            // Skip projector artifacts (.mmproj or *.gguf that contain projector keywords)
            if lower.contains("mmproj") || lower.contains("projector") || lower.contains("image_proj") {
                continue
            }
            if lower.hasSuffix(".gguf") {
                let label = Self.label(for: file.path, repoID: repoID, ext: ".gguf")
                // Skip duplicate labels within the same repo (common with mirrored filenames)
                guard seenLabels.insert(label).inserted else { continue }
                let url = URL(string: "https://huggingface.co/\(repoID)/resolve/main/\(file.path)?download=1")!
                let cfg = URL(string: "https://huggingface.co/\(repoID)/raw/main/config.json")
                quants.append(QuantInfo(label: label,
                                       format: .gguf,
                                       sizeBytes: file.size,
                                       downloadURL: url,
                                       sha256: file.sha256,
                                       configURL: cfg))
            }
        }
        // MLX detection (prefer safetensors shards, then NPZ, then weights.json)
        let safetensors = files.first(where: { $0.path.lowercased().hasSuffix(".safetensors") })
        let npz = files.first(where: { $0.path.lowercased().hasSuffix(".npz") })
        let weightsJson = files.first(where: { $0.path.lowercased().hasSuffix("weights.json") })
        if let picked = safetensors ?? npz ?? weightsJson {
            let url = URL(string: "https://huggingface.co/\(repoID)/resolve/main/\(picked.path)")!
            let cfg = URL(string: "https://huggingface.co/\(repoID)/raw/main/config.json")
            let label = Self.mlxLabel(for: picked.path, repoID: repoID)
            quants.append(QuantInfo(label: label,
                                   format: .mlx,
                                   sizeBytes: picked.size,
                                   downloadURL: url,
                                   sha256: picked.sha256,
                                   configURL: cfg))
        }
        return quants
    }

    private static func label(for path: String, repoID: String, ext: String) -> String {
        // Start from the file path, strip common prefixes/suffixes and normalise separators
        var base = path
        if let repoName = repoID.split(separator: "/").last.map(String.init) {
            if base.lowercased().hasPrefix(repoName.lowercased()) {
                base = String(base.dropFirst(repoName.count))
            }
        }
        if base.lowercased().hasSuffix(ext) { base = String(base.dropLast(ext.count)) }
        var working = base.replacingOccurrences(of: "-", with: "_")
        working = working.replacingOccurrences(of: ".", with: "_")
        working = working.trimmingCharacters(in: CharacterSet(charactersIn: "_."))

        // Prefer explicit GGUF quant patterns that include digits (avoids matching "qwen")
        // Examples matched: q4_k_m, q3_k_s, q8_0, iq2_xxs, iq4_nl, q5_1
        let pattern = "(?i)(iq\\d+[a-z0-9_]*|q\\d+[a-z0-9_]*)"
        if let last = lastRegexMatch(in: working, pattern: pattern) {
            return last.uppercased()
        }

        // Fallback: try a looser trailing quant capture near the end after the last underscore
        if let idx = working.lastIndex(of: "_") {
            let tail = String(working[working.index(after: idx)...])
            if let last = lastRegexMatch(in: tail, pattern: pattern) {
                return last.uppercased()
            }
        }

        // As a final fallback, return the cleaned filename component
        return working.uppercased()
    }

    private static func lastRegexMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let full = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: full)
        guard let m = matches.last, let r = Range(m.range, in: text) else { return nil }
        return String(text[r])
    }

    private static func mlxLabel(for path: String, repoID: String) -> String {
        let combined = (repoID + " " + path).lowercased()
        if let r = combined.range(of: #"(?:q|int|fp)[ _-]?(\d{1,2})|(\d{1,2})[ _-]?bit"#, options: .regularExpression) {
            let match = String(combined[r])
            let digits = match.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
            if let bits = Int(digits) {
                if bits == 16 { return "F16" }
                return "INT\(bits)"
            }
        }
        return "MLX"
    }

    static func shortLabel(from label: String, format: ModelFormat) -> String {
        switch format {
        case .gguf:
            // Prefer full informative token over just Q-number
            let pat = #"(?i)(iq\d+[a-z0-9_]*|q\d+[a-z0-9_]*)"#
            if let regex = try? NSRegularExpression(pattern: pat),
               let r = regex.matches(in: label, options: [], range: NSRange(label.startIndex..<label.endIndex, in: label)).last,
               let rr = Range(r.range, in: label) {
                return String(label[rr]).uppercased()
            }
            return label.uppercased()
        case .mlx:
            if let r = label.range(of: #"(\d{1,2})"#, options: .regularExpression) {
                let digits = label[r]
                return "\(digits)bit"
            }
            return label
        case .slm:
            return label
        case .apple:
            return label
        }
    }
}
