// QuantExtractor.swift
import Foundation

public struct RepoFile { let path: String; let size: Int64; let sha256: String? }

public enum QuantExtractor {
    static func extract(from files: [RepoFile], repoID: String) -> [QuantInfo] {
        var quants: [QuantInfo] = []
        var seenLabels: Set<String> = []
        struct GGUFGroup {
            let key: String
            var files: [RepoFile] = []
        }

        var groupsByKey: [String: GGUFGroup] = [:]
        var groupOrder: [String] = []

        for file in files {
            let lower = file.path.lowercased()
            // Skip projector artifacts (.mmproj or *.gguf that contain projector keywords)
            if lower.contains("mmproj") || lower.contains("projector") || lower.contains("image_proj") {
                continue
            }
            guard lower.hasSuffix(".gguf") else { continue }

            let key = GGUFShardNaming.splitGroupKey(forPath: file.path) ?? "single:\(file.path)"
            if groupsByKey[key] == nil {
                groupsByKey[key] = GGUFGroup(key: key, files: [])
                groupOrder.append(key)
            }
            var existing = groupsByKey[key] ?? GGUFGroup(key: key, files: [])
            existing.files.append(file)
            groupsByKey[key] = existing
        }

        let cfg = URL(string: "https://huggingface.co/\(repoID)/raw/main/config.json")

        for key in groupOrder {
            guard let group = groupsByKey[key], !group.files.isEmpty else { continue }

            let splitInfos: [(file: RepoFile, info: GGUFShardNaming.SplitInfo)] = group.files.compactMap { file in
                guard let info = GGUFShardNaming.parseSplitPath(file.path) else { return nil }
                return (file, info)
            }

            let isSplitGroup = !splitInfos.isEmpty
            if isSplitGroup && splitInfos.count != group.files.count {
                print("[QuantExtractor] Skipping mixed GGUF split/non-split group: \(group.key)")
                continue
            }

            if isSplitGroup {
                let expectedCounts = Set(splitInfos.map { $0.info.partCount })
                guard expectedCounts.count == 1, let expected = expectedCounts.first else {
                    print("[QuantExtractor] Skipping GGUF split group with inconsistent part counts: \(group.key)")
                    continue
                }

                var uniqueByPart: [Int: (file: RepoFile, info: GGUFShardNaming.SplitInfo)] = [:]
                for entry in splitInfos where uniqueByPart[entry.info.partIndex] == nil {
                    uniqueByPart[entry.info.partIndex] = entry
                }
                guard uniqueByPart.count == expected else {
                    print("[QuantExtractor] Skipping incomplete GGUF split group (\(uniqueByPart.count)/\(expected)): \(group.key)")
                    continue
                }

                let ordered = uniqueByPart.values.sorted { a, b in
                    if a.info.partIndex != b.info.partIndex { return a.info.partIndex < b.info.partIndex }
                    return a.file.path < b.file.path
                }
                guard let primary = ordered.first(where: { $0.info.partIndex == 1 }) ?? ordered.first else { continue }

                let label = Self.label(for: primary.file.path, repoID: repoID, ext: ".gguf")
                guard seenLabels.insert(label).inserted else { continue }

                let parts: [QuantInfo.DownloadPart] = ordered.map { entry in
                    QuantInfo.DownloadPart(
                        path: entry.file.path,
                        sizeBytes: entry.file.size,
                        sha256: entry.file.sha256,
                        downloadURL: URL(string: "https://huggingface.co/\(repoID)/resolve/main/\(entry.file.path)?download=1")!
                    )
                }
                let totalBytes = parts.reduce(into: Int64(0)) { $0 += max($1.sizeBytes, 0) }

                quants.append(QuantInfo(
                    label: label,
                    format: .gguf,
                    sizeBytes: totalBytes,
                    downloadURL: parts.first(where: { GGUFShardNaming.parseSplitPath($0.path)?.partIndex == 1 })?.downloadURL ?? parts[0].downloadURL,
                    sha256: nil,
                    configURL: cfg,
                    downloadParts: parts
                ))
                continue
            }

            guard let file = group.files.first else { continue }
            let label = Self.label(for: file.path, repoID: repoID, ext: ".gguf")
            // Skip duplicate labels within the same repo (common with mirrored filenames)
            guard seenLabels.insert(label).inserted else { continue }
            let url = URL(string: "https://huggingface.co/\(repoID)/resolve/main/\(file.path)?download=1")!
            quants.append(QuantInfo(label: label,
                                   format: .gguf,
                                   sizeBytes: file.size,
                                   downloadURL: url,
                                   sha256: file.sha256,
                                   configURL: cfg))
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

        // ExecuTorch detection (.pte program files)
        let pteFiles = files.filter { $0.path.lowercased().hasSuffix(".pte") }
        if !pteFiles.isEmpty {
            let orderedPTE = pteFiles.sorted { lhs, rhs in
                let l = lhs.path.lowercased()
                let r = rhs.path.lowercased()
                let lPrimary = l.hasSuffix("/model.pte") || l == "model.pte"
                let rPrimary = r.hasSuffix("/model.pte") || r == "model.pte"
                if lPrimary != rPrimary { return lPrimary && !rPrimary }
                return l < r
            }
            for file in orderedPTE {
                let label = Self.etLabel(for: file.path, repoID: repoID)
                guard seenLabels.insert(label).inserted else { continue }
                let url = URL(string: "https://huggingface.co/\(repoID)/resolve/main/\(file.path)?download=1")!
                let cfg = URL(string: "https://huggingface.co/\(repoID)/raw/main/tokenizer_config.json")
                    ?? URL(string: "https://huggingface.co/\(repoID)/raw/main/config.json")
                quants.append(
                    QuantInfo(
                        label: label,
                        format: .et,
                        sizeBytes: file.size,
                        downloadURL: url,
                        sha256: file.sha256,
                        configURL: cfg
                    )
                )
            }
        }

        // CoreML / ANE detection (single install artifact, no quant tiers)
        if let aneQuant = aneQuant(from: files, repoID: repoID) {
            if seenLabels.insert(aneQuant.label).inserted {
                quants.append(aneQuant)
            }
        }
        return quants
    }

    private static func label(for path: String, repoID: String, ext: String) -> String {
        _ = ext // kept to preserve the existing signature and call sites
        return GGUFShardNaming.normalizedQuantLabel(for: path, repoID: repoID)
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

    private static func etLabel(for path: String, repoID: String) -> String {
        let combined = (repoID + " " + path).lowercased()
        if combined.contains("xnnpack") { return "ET-XNNPACK" }
        if combined.contains("coreml") || combined.contains("core-ml") { return "ET-CoreML" }
        if combined.contains("mps") || combined.contains("metal") { return "ET-MPS" }
        return "ET"
    }

    private static let aneSidecarNames: [String] = [
        "meta.yaml",
        "meta.yml",
        "tokenizer.json",
        "tokenizer_config.json",
        "special_tokens_map.json",
        "added_tokens.json",
        "tokenizer.model",
        "spiece.model",
        "sentencepiece.bpe.model",
        "vocab.json",
        "vocab.txt",
        "merges.txt",
        "config.json",
        "generation_config.json",
        "chat_template.json",
        "chat_template.jinja"
    ]

    private static func aneQuant(from files: [RepoFile], repoID: String) -> QuantInfo? {
        guard !files.isEmpty else { return nil }

        let roots = Set(files.compactMap { coreMLRootPath(from: $0.path) })
        guard !roots.isEmpty else { return nil }

        let prioritizedRoots = roots.sorted { lhs, rhs in
            let lp = coreMLPriority(for: lhs)
            let rp = coreMLPriority(for: rhs)
            if lp != rp { return lp < rp }
            if lhs.count != rhs.count { return lhs.count < rhs.count }
            return lhs < rhs
        }

        var orderedPaths: [String] = []
        var seen = Set<String>()

        for root in prioritizedRoots {
            let rootLower = root.lowercased()
            let isContainer = rootLower.hasSuffix(".mlmodelc") || rootLower.hasSuffix(".mlpackage")
            let matches = files
                .map(\.path)
                .filter { path in
                    if isContainer {
                        return path == root || path.hasPrefix(root + "/")
                    }
                    return path == root
                }
                .sorted()
            for match in matches where seen.insert(match).inserted {
                orderedPaths.append(match)
            }
        }

        if !orderedPaths.isEmpty {
            let sidecars = files
                .map(\.path)
                .filter { path in
                    let lower = path.lowercased()
                    let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()
                    return aneSidecarNames.contains(name)
                        || lower.hasSuffix("/tokenizer.json")
                        || lower.hasSuffix("/tokenizer_config.json")
                        || lower.hasSuffix("/config.json")
                }
                .sorted()
            for sidecar in sidecars where seen.insert(sidecar).inserted {
                orderedPaths.append(sidecar)
            }
        }

        guard !orderedPaths.isEmpty else { return nil }

        var filesByPath: [String: RepoFile] = [:]
        for file in files where filesByPath[file.path] == nil {
            filesByPath[file.path] = file
        }
        let parts: [QuantInfo.DownloadPart] = orderedPaths.compactMap { path in
            guard let file = filesByPath[path] else { return nil }
            guard let downloadURL = resolveDownloadURL(repoID: repoID, path: path) else { return nil }
            return QuantInfo.DownloadPart(
                path: path,
                sizeBytes: file.size,
                sha256: file.sha256,
                downloadURL: downloadURL
            )
        }
        guard !parts.isEmpty else { return nil }

        let totalBytes = parts.reduce(into: Int64(0)) { sum, part in
            sum += max(part.sizeBytes, 0)
        }

        let primaryPath = prioritizedRoots.first.flatMap { root in
            parts.first(where: { part in
                part.path == root || part.path.hasPrefix(root + "/")
            })?.path
        }
        let primaryPart = parts.first(where: { $0.path == primaryPath }) ?? parts[0]
        let cfg = URL(string: "https://huggingface.co/\(repoID)/raw/main/config.json")

        return QuantInfo(
            label: "CML",
            format: .ane,
            sizeBytes: totalBytes,
            downloadURL: primaryPart.downloadURL,
            sha256: nil,
            configURL: cfg,
            downloadParts: parts
        )
    }

    private static func coreMLPriority(for path: String) -> Int {
        let lower = path.lowercased()
        if lower.hasSuffix(".mlmodelc") { return 0 }
        if lower.hasSuffix(".mlpackage") { return 1 }
        if lower.hasSuffix(".mlmodel") { return 2 }
        return 9
    }

    private static func coreMLRootPath(from path: String) -> String? {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let components = normalized.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.isEmpty else { return nil }

        for idx in components.indices {
            let component = components[idx].lowercased()
            if component.hasSuffix(".mlmodelc") || component.hasSuffix(".mlpackage") {
                return components[components.startIndex...idx].map(String.init).joined(separator: "/")
            }
        }

        if normalized.lowercased().hasSuffix(".mlmodel") {
            return components.map(String.init).joined(separator: "/")
        }
        return nil
    }

    private static func resolveDownloadURL(repoID: String, path: String) -> URL? {
        let escapedRepo = repoID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repoID
        let encodedPath = path
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { component in
                String(component).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(component)
            }
            .joined(separator: "/")
        return URL(string: "https://huggingface.co/\(escapedRepo)/resolve/main/\(encodedPath)?download=1")
    }

    static func shortLabel(from label: String, format: ModelFormat) -> String {
        switch format {
        case .gguf:
            // Prefer full informative token over just Q-number
            let normalized = label.replacingOccurrences(of: "-", with: "_")
            let pat = #"(?i)(ud_(?:iq\d+[a-z0-9_]*|q\d+[a-z0-9_]*|tq\d+[a-z0-9_]*|mxfp\d+(?:_moe)?)|iq\d+[a-z0-9_]*|q\d+[a-z0-9_]*|tq\d+[a-z0-9_]*|mxfp\d+(?:_moe)?)"#
            if let regex = try? NSRegularExpression(pattern: pat),
               let r = regex.matches(in: normalized, options: [], range: NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)).last,
               let rr = Range(r.range, in: normalized) {
                return String(normalized[rr]).uppercased()
            }
            return normalized.uppercased()
        case .mlx:
            if let r = label.range(of: #"(\d{1,2})"#, options: .regularExpression) {
                let digits = label[r]
                return "\(digits)bit"
            }
            return label
        case .et:
            return label
        case .ane:
            return label
        case .afm:
            return label
        }
    }
}
