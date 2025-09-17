// LeapCatalogService.swift
import Foundation

private final class LeapCatalogBundleFinder {}

private extension Bundle {
    static var leapCatalog: Bundle {
#if SWIFT_PACKAGE
        return .module
#else
        return Bundle(for: LeapCatalogBundleFinder.self)
#endif
    }
}

enum LeapCatalogService {

    static func loadCatalog() async -> [LeapCatalogEntry] {
        struct Meta: Decodable {
            struct Sibling: Decodable { let rfilename: String; let size: Int?; let lfs: LFS?; struct LFS: Decodable { let sha256: String?; let size: Int? } }
            let siblings: [Sibling]?
        }

        // Fetch the list of available .bundle files from the LeapBundles repo
        var comps = URLComponents(string: "https://huggingface.co/api/models/LiquidAI/LeapBundles")!
        comps.queryItems = [URLQueryItem(name: "full", value: "1")]

        var req = URLRequest(url: comps.url!)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = UserDefaults.standard.string(forKey: "huggingFaceToken"), !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode >= 400 { return [] }
            let meta = try JSONDecoder().decode(Meta.self, from: data)
            let siblings = meta.siblings ?? []

            // Map every .bundle file into a LeapCatalogEntry. Slug is the base name without extension.
            var entries: [LeapCatalogEntry] = []
            for sib in siblings where sib.rfilename.lowercased().hasSuffix(".bundle") {
                let fname = sib.rfilename
                let slug = String(fname.dropLast(7)) // remove ".bundle"
                let size = Int64(sib.lfs?.size ?? sib.size ?? 0)
                let sha = sib.lfs?.sha256
                let display = name(for: slug) ?? slug
                entries.append(LeapCatalogEntry(slug: slug, displayName: display, sizeBytes: size, sha256: sha))
            }

            // De-duplicate by slug and provide stable ordering by displayName
            var seen = Set<String>()
            let deduped = entries.filter { seen.insert($0.slug).inserted }
            return deduped.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        } catch {
            return []
        }
    }

    static func name(for slug: String) -> String? {
        // Always derive a clean display name from the slug
        return prettyName(from: slug)
    }

    /// Heuristic: whether a quantization slug indicates a vision-capable model
    static func isVisionQuantizationSlug(_ slug: String) -> Bool {
        let s = slug.lowercased()
        // Obvious keywords
        if s.contains("vision") || s.contains("vlm") { return true }
        // Common tokenized forms of "vl" in slugs: start, middle, end, with - or _ separators
        if s.range(of: "(?:^|[-_])vl(?:[-_]|$)", options: .regularExpression) != nil { return true }
        // Additional loose forms like "-vl" or "vl-" when not both sides are present
        if s.hasSuffix("-vl") || s.hasSuffix("_vl") || s.hasPrefix("vl-") || s.hasPrefix("vl_") { return true }
        if s.contains("-vl") || s.contains("_vl") || s.contains("vl-") || s.contains("vl_") { return true }
        return false
    }

    /// Fallback filesystem heuristic: scan the .bundle contents for vision indicators.
    /// This is a best-effort check to complement slug detection when metadata is missing.
    static func bundleLikelyVision(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return false }
        let indicators = ["vision", "vlm", "clip", "siglip", "image_processor", "image-processor", "imageprocessor"]
        let name = url.lastPathComponent.lowercased()
        if indicators.contains(where: { name.contains($0) }) { return true }
        if let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
            var scanned = 0
            for case let p as URL in e {
                scanned += 1
                if scanned > 2000 { break }
                let lower = p.lastPathComponent.lowercased()
                if indicators.contains(where: { lower.contains($0) }) { return true }
            }
        }
        return false
    }

    private static func prettyName(from slug: String) -> String {
        // Goal: turn quantization slugs into clean titles, e.g.:
        //  - "LFM2-1.2B-8da4w_output_8da8w-seq_4096" -> "Lfm2 1.2B"
        //  - "lfm2-350m-extract-8da4w"            -> "Lfm2 350M"
        //  - "qwen3-0_6b_8da4w_4096"               -> "Qwen3 0.6B"

        // Normalize separators and dashes
        var s = slug
            .replacingOccurrences(of: "–", with: "-") // en dash
            .replacingOccurrences(of: "—", with: "-") // em dash
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Family is the first hyphen-separated token
        let familyToken = s.split(separator: "-").first.map(String.init) ?? s
        let family = familyToken.replacingOccurrences(of: "_", with: "-").capitalized

        // Find a size token anywhere in the slug:
        //  - supports 350m, 1.2b, 0_6b, 7b, 8x7b
        //  - avoids context length like 4096 (no trailing b/m)
        let patterns = [
            #"(?i)\d+(?:[._]\d+)?x\d+[bm]"#, // 8x7b
            #"(?i)\d+(?:[._]\d+)?[bm]"#       // 1.2b, 350m, 7b, 0_6b
        ]
        var sizeToken: String?
        for pat in patterns {
            if let r = s.range(of: pat, options: .regularExpression) {
                sizeToken = String(s[r])
                break
            }
        }

        let specialization = specializationName(from: s)

        guard var size = sizeToken else {
            if let spec = specialization {
                return "\(family) \(spec)"
            }
            return family // Fallback to family only
        }

        // Normalize number separators and the unit
        size = size.replacingOccurrences(of: "_", with: ".")
        // Uppercase the trailing unit while preserving any "x" patterns
        // Split off the unit (last character if it is b/m)
        if let last = size.last, last == "b" || last == "B" || last == "m" || last == "M" {
            let unit = (last == "m" || last == "M") ? "M" : "B"
            size.removeLast()
            size += unit
        }

        if let spec = specialization {
            return "\(family) \(size) \(spec)"
        }
        return "\(family) \(size)"
    }

    private static func specializationName(from slug: String) -> String? {
        let lower = slug.lowercased()
        let mapping: [(String, String)] = [
            ("tool", "Tool"),
            ("extract", "Extract"),
            ("rag", "RAG"),
            ("enjp", "ENJP")
        ]
        for (key, value) in mapping {
            let pattern = "(?:^|[-_])" + key + "(?:[-_]|$)"
            if lower.range(of: pattern, options: .regularExpression) != nil {
                return value
            }
        }
        return nil
    }
}
