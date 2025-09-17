// GGUFMetadata.swift
import Foundation

enum GGUFMetadata {
    static func layerCount(at url: URL) -> Int? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        var offset = 0

        func readU32() -> UInt32? {
            guard offset + 4 <= data.count else { return nil }
            let value = data.subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: UInt32.self) }
            offset += 4
            return UInt32(littleEndian: value)
        }

        func readU64() -> UInt64? {
            guard offset + 8 <= data.count else { return nil }
            let value = data.subdata(in: offset..<offset+8).withUnsafeBytes { $0.load(as: UInt64.self) }
            offset += 8
            return UInt64(littleEndian: value)
        }

        func readString(len: Int) -> String? {
            guard offset + len <= data.count else { return nil }
            let sub = data.subdata(in: offset..<offset+len)
            offset += len
            return String(data: sub, encoding: .utf8)
        }
        guard let magic = readString(len: 4), magic == "GGUF" else { return nil }
        guard let _ = readU32() else { return nil } // version
        guard let _ = readU64() else { return nil } // tensor count
        guard let kvCount = readU64().map(Int.init) else { return nil }
        for _ in 0..<kvCount {
            guard let klen = readU64().map(Int.init) else { return nil }
            guard let key = readString(len: klen) else { return nil }
            guard let type = readU32() else { return nil }
            switch type {
            case 4: // uint32
                if let val = readU32().map(Int.init),
                   key.contains("block_count") ||
                   key.contains("n_layer") ||
                   key.contains("num_hidden_layers") ||
                   key.contains("layer_count") {
                    return val
                }
            case 10: // uint64
                if let val = readU64().map(Int.init),
                   key.contains("block_count") ||
                   key.contains("n_layer") ||
                   key.contains("num_hidden_layers") ||
                   key.contains("layer_count") {
                    return val
                }
            case 8: // string
                guard let len = readU64().map(Int.init) else { return nil }
                offset += len
            case 9: // array
                guard let elemType = readU32(), let count = readU64() else { return nil }
                let size: Int
                switch elemType {
                case 0,1,7: size = 1
                case 2,3:   size = 2
                case 4,5,6: size = 4
                case 10,11,12: size = 8
                case 8:
                    guard let arrLen = readU64() else { return nil }
                    size = 0
                    if offset + Int(arrLen) > data.count { return nil }
                    offset += Int(arrLen)
                    continue
                default: size = 4
                }
                if offset + Int(count) * size > data.count { return nil }
                offset += Int(count) * size
                default:
                    let size: Int
                    switch type {
                    case 0,1,7: size = 1
                    case 2,3:   size = 2
                    case 4,5,6: size = 4
                    case 10,11,12: size = 8
                    default: size = 0
                    }
                    if offset + size > data.count { return nil }
                    offset += size
            }
        }
        return nil
    }

    static func contextLength(at url: URL) -> Int? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        var offset = 0
        func readU32() -> UInt32? {
            guard offset + 4 <= data.count else { return nil }
            let value = data.subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: UInt32.self) }
            offset += 4
            return UInt32(littleEndian: value)
        }
        func readU64() -> UInt64? {
            guard offset + 8 <= data.count else { return nil }
            let value = data.subdata(in: offset..<offset+8).withUnsafeBytes { $0.load(as: UInt64.self) }
            offset += 8
            return UInt64(littleEndian: value)
        }
        func readString(len: Int) -> String? {
            guard offset + len <= data.count else { return nil }
            let sub = data.subdata(in: offset..<offset+len)
            offset += len
            return String(data: sub, encoding: .utf8)
        }
        guard let magic = readString(len: 4), magic == "GGUF" else { return nil }
        guard let _ = readU32() else { return nil }
        guard let _ = readU64() else { return nil }
        guard let kvCount = readU64().map(Int.init) else { return nil }
        for _ in 0..<kvCount {
            guard let klen = readU64().map(Int.init) else { return nil }
            guard let key = readString(len: klen) else { return nil }
            guard let type = readU32() else { return nil }
            switch type {
            case 4:
                if key.contains("n_ctx"), let val = readU32().map(Int.init) {
                    return val
                }
            case 10:
                if key.contains("n_ctx"), let val = readU64().map(Int.init) {
                    return val
                }
            case 8:
                guard let len = readU64().map(Int.init) else { return nil }
                offset += len
            case 9:
                guard let et = readU32(), let count = readU64() else { return nil }
                let size: Int
                switch et {
                case 0,1,7: size = 1
                case 2,3: size = 2
                case 4,5,6: size = 4
                case 10,11,12: size = 8
                case 8:
                    guard let arrLen = readU64() else { return nil }
                    size = 0
                    if offset + Int(arrLen) > data.count { return nil }
                    offset += Int(arrLen)
                    continue
                default: size = 4
                }
                if offset + Int(count) * size > data.count { return nil }
                offset += Int(count) * size
            default:
                let size: Int
                switch type {
                case 0,1,7: size = 1
                case 2,3: size = 2
                case 4,5,6: size = 4
                case 10,11,12: size = 8
                default: size = 0
                }
                if offset + size > data.count { return nil }
                offset += size
            }
        }
        return nil
    }

    static func chatTemplate(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        var offset = 0

        func readU32() -> UInt32? {
            guard offset + 4 <= data.count else { return nil }
            let value = data.subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: UInt32.self) }
            offset += 4
            return UInt32(littleEndian: value)
        }

        func readU64() -> UInt64? {
            guard offset + 8 <= data.count else { return nil }
            let value = data.subdata(in: offset..<offset+8).withUnsafeBytes { $0.load(as: UInt64.self) }
            offset += 8
            return UInt64(littleEndian: value)
        }

        func readString(len: Int) -> String? {
            guard offset + len <= data.count else { return nil }
            let sub = data.subdata(in: offset..<offset+len)
            offset += len
            return String(data: sub, encoding: .utf8)
        }

        guard let magic = readString(len: 4), magic == "GGUF" else { return nil }
        guard let _ = readU32() else { return nil }
        guard let _ = readU64() else { return nil }
        guard let kvCount = readU64().map(Int.init) else { return nil }
        for _ in 0..<kvCount {
            guard let klen = readU64().map(Int.init) else { return nil }
            guard let key = readString(len: klen) else { return nil }
            guard let type = readU32() else { return nil }
            switch type {
            case 8: // string
                guard let len = readU64().map(Int.init) else { return nil }
                if key.contains("chat_template"), let tmpl = readString(len: len) {
                    return tmpl
                }
                offset += len
            case 9: // array
                guard let elemType = readU32(), let count = readU64() else { return nil }
                let size: Int
                switch elemType {
                case 0,1,7: size = 1
                case 2,3:   size = 2
                case 4,5,6: size = 4
                case 10,11,12: size = 8
                case 8:
                    guard let arrLen = readU64() else { return nil }
                    size = 0
                    if offset + Int(arrLen) > data.count { return nil }
                    offset += Int(arrLen)
                    continue
                default: size = 4
                }
                if offset + Int(count) * size > data.count { return nil }
                offset += Int(count) * size
            default:
                let size: Int
                switch type {
                case 0,1,7: size = 1
                case 2,3:   size = 2
                case 4,5,6: size = 4
                case 10,11,12: size = 8
                default: size = 0
                }
                if offset + size > data.count { return nil }
                offset += size
            }
        }
        return nil
    }

    /// Scan GGUF header/kv for tool-related markers (chat_template hints or added tokens)
    static func suggestsTools(at url: URL) -> Bool {
        // Attempt to read a limited header where GGUF metadata lives for speed
        let maxScanBytes = 8 * 1024 * 1024 // 8 MB
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: maxScanBytes), head.count > 0 else { return false }

        // Strong markers commonly present in tool-capable chat templates or token lists
        let indicators: [String] = [
            "tools", "tool_call", "tool_calls", "function_call", "function_calls",
            "tool_result", "tool_response", "function_response",
            "<tool_call>", "</tool_call>", "<tools>", "</tools>",
            #""role":\s*"tool"#,
            "<|tool_call|>", "<|tool_response|>",
            "assistant_tools", "tool_call_id"
        ]
        for key in indicators {
            if let needle = key.data(using: .utf8), head.range(of: needle) != nil { return true }
        }
        // Fallback: if explicit chat_template is present, try to parse it and re-check
        if let tmpl = chatTemplate(at: url), !tmpl.isEmpty {
            let lower = tmpl.lowercased()
            for k in indicators where lower.contains(k.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)) {
                return true
            }
        }
        return false
    }

    /// Heuristic detection for vision-capable GGUF models.
    /// Scans the header/kv section for vision-related keys to avoid loading the entire file.
    static func isVisionLikely(at url: URL) -> Bool {
        // Attempt to read only the first few megabytes where GGUF metadata resides
        let maxScanBytes = 8 * 1024 * 1024 // 8 MB
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: maxScanBytes), head.count > 0 else { return false }

        // Common indicators of VLM/vision support present in GGUF kv keys or text
        let indicators: [String] = [
            "mm_projector", "mm_vision", "vision_tower", "vision", "visual",
            "clip", "siglip", "image_token", "image_grid", "image_size",
            "llava", "qwen-vl", "internvl", "phi-3-vision", "glm-4v", "pixtral",
            "multimodal", "vlm"
        ]
        for key in indicators {
            if let needle = key.data(using: .utf8), head.range(of: needle) != nil { return true }
        }
        return false
    }

    /// Stronger check for merged vision models: verify projector-related metadata/tensors exist.
    /// Returns true only when the GGUF contains definitive projector indicators such as
    /// keys like `llava.projector_type`, or tensor/kv names containing `mmproj`, `mm_projector`, or `vision_tower`.
    static func hasMultimodalProjector(at url: URL) -> Bool {
        // Read the first chunk where GGUF header + kvs live
        let maxScanBytes = 16 * 1024 * 1024 // 16 MB
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: maxScanBytes), head.count > 0 else { return false }

        var data = head
        var offset = 0

        func readU32() -> UInt32? {
            guard offset + 4 <= data.count else { return nil }
            let value = data.subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: UInt32.self) }
            offset += 4
            return UInt32(littleEndian: value)
        }

        func readU64() -> UInt64? {
            guard offset + 8 <= data.count else { return nil }
            let value = data.subdata(in: offset..<offset+8).withUnsafeBytes { $0.load(as: UInt64.self) }
            offset += 8
            return UInt64(littleEndian: value)
        }

        func readString(len: Int) -> String? {
            guard offset + len <= data.count else { return nil }
            let sub = data.subdata(in: offset..<offset+len)
            offset += len
            return String(data: sub, encoding: .utf8)
        }

        // Parse GGUF header minimally to iterate kvs
        guard let magic = readString(len: 4), magic == "GGUF" else {
            // Fallback: strong substring scan of header bytes
            return ["llava.projector_type", "mmproj", "mm_projector", "vision_tower"].contains { key in
                head.range(of: key.data(using: .utf8)!) != nil
            }
        }
        guard readU32() != nil else { return false } // version
        _ = readU64() // tensor count (unused)
        guard let kvCount = readU64().map(Int.init) else { return false }

        let projectorIndicators = [
            "llava.projector_type",
            "mmproj",
            "mm_projector",
            "vision_tower"
        ]

        for _ in 0..<kvCount {
            guard let klen = readU64().map(Int.init), let key = readString(len: klen), let type = readU32() else {
                break
            }
            let lowerKey = key.lowercased()
            if projectorIndicators.contains(where: { lowerKey.contains($0) }) {
                return true
            }
            switch type {
            case 8: // string
                guard let len = readU64().map(Int.init) else { return false }
                // Optionally, value can also contain indicators
                if let value = readString(len: len)?.lowercased(), projectorIndicators.contains(where: { value.contains($0) }) {
                    return true
                }
            case 9: // array
                guard let elemType = readU32(), let count = readU64() else { return false }
                let size: Int
                switch elemType {
                case 0,1,7: size = 1
                case 2,3:   size = 2
                case 4,5,6: size = 4
                case 10,11,12: size = 8
                case 8:
                    // Array of strings: gguf packs an aggregate length; skip payload
                    guard let arrLen = readU64() else { return false }
                    if offset + Int(arrLen) > data.count { return false }
                    offset += Int(arrLen)
                    continue
                default: size = 4
                }
                if offset + Int(count) * size > data.count { return false }
                offset += Int(count) * size
            default:
                let size: Int
                switch type {
                case 0,1,7: size = 1
                case 2,3:   size = 2
                case 4,5,6: size = 4
                case 10,11,12: size = 8
                default: size = 0
                }
                if offset + size > data.count { return false }
                offset += size
            }
        }

        // As a fallback, search the scanned header for strong projector tokens
        for token in projectorIndicators {
            if let needle = token.data(using: .utf8), head.range(of: needle) != nil {
                return true
            }
        }
        return false
    }
}
