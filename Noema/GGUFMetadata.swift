// GGUFMetadata.swift
import Foundation

enum GGUFMetadata {
    static func architectureInfo(at url: URL) -> (architecture: String, name: String?)? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        var offset = 0

        func ensureCapacity(_ length: Int) -> Bool {
            if length < 0 { return false }
            return offset <= data.count - length
        }

        func skipBytes(_ length: Int) -> Bool {
            guard ensureCapacity(length) else { return false }
            offset += length
            return true
        }

        func readU32() -> UInt32? {
            guard ensureCapacity(4) else { return nil }
            let value = data.subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: UInt32.self) }
            offset += 4
            return UInt32(littleEndian: value)
        }

        func readU64() -> UInt64? {
            guard ensureCapacity(8) else { return nil }
            let value = data.subdata(in: offset..<offset+8).withUnsafeBytes { $0.load(as: UInt64.self) }
            offset += 8
            return UInt64(littleEndian: value)
        }

        func readString(len: Int) -> String? {
            guard ensureCapacity(len) else { return nil }
            let sub = data.subdata(in: offset..<offset+len)
            offset += len
            return String(data: sub, encoding: .utf8)
        }

        func skipScalar(ofType type: UInt32) -> Bool {
            let size: Int
            switch type {
            case 0, 1, 7: size = 1
            case 2, 3: size = 2
            case 4, 5, 6: size = 4
            case 10, 11, 12: size = 8
            default: size = 0
            }
            guard size > 0 else { return false }
            return skipBytes(size)
        }

        func skipArray(elementType: UInt32, count: UInt64) -> Bool {
            if elementType == 8 {
                guard count <= UInt64(Int.max) else { return false }
                for _ in 0..<Int(count) {
                    guard let len = readU64().map(Int.init) else { return false }
                    guard skipBytes(len) else { return false }
                }
                return true
            }

            let elementSize: Int
            switch elementType {
            case 0, 1, 7: elementSize = 1
            case 2, 3: elementSize = 2
            case 4, 5, 6: elementSize = 4
            case 10, 11, 12: elementSize = 8
            default: elementSize = 4
            }
            guard elementSize > 0 else { return false }
            let maxElements = UInt64(Int.max) / UInt64(elementSize)
            guard count <= maxElements else { return false }
            return skipBytes(Int(count) * elementSize)
        }

        func architectureSpecificity(of string: String) -> Int {
            var score = string.count
            if string.contains("/") { score += 25 }
            if string.contains("-") { score += 10 }
            if string.rangeOfCharacter(from: .decimalDigits) != nil { score += 5 }
            return score
        }

        guard let magic = readString(len: 4), magic == "GGUF" else { return nil }
        guard readU32() != nil else { return nil }
        guard readU64() != nil else { return nil }
        guard let kvCount = readU64().map(Int.init) else { return nil }

        var architecture: String?
        var name: String?

        for _ in 0..<kvCount {
            guard let keyLen = readU64().map(Int.init), let key = readString(len: keyLen) else { return nil }
            guard let type = readU32() else { return nil }

            switch type {
            case 8:
                guard let len = readU64().map(Int.init) else { return nil }
                guard let value = readString(len: len)?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
                if key == "general.architecture", !value.isEmpty {
                    architecture = value
                } else if key == "general.name", !value.isEmpty {
                    name = value
                }
            case 9:
                guard let elemType = readU32(), let count = readU64() else { return nil }
                if key == "general.architectures", elemType == 8 {
                    guard count <= UInt64(Int.max) else { return nil }
                    var candidate: (value: String, score: Int)?
                    for _ in 0..<Int(count) {
                        guard let len = readU64().map(Int.init), let value = readString(len: len) else { return nil }
                        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            let score = architectureSpecificity(of: trimmed)
                            if let current = candidate {
                                if score > current.score { candidate = (trimmed, score) }
                            } else {
                                candidate = (trimmed, score)
                            }
                        }
                    }
                    if let candidate {
                        if let current = architecture {
                            if candidate.score > architectureSpecificity(of: current) {
                                architecture = candidate.value
                            }
                        } else {
                            architecture = candidate.value
                        }
                    }
                } else {
                    guard skipArray(elementType: elemType, count: count) else { return nil }
                }
            default:
                guard skipScalar(ofType: type) else { return nil }
            }

            if architecture != nil && name != nil {
                break
            }
        }

        guard let architecture else { return nil }
        return (architecture, name)
    }

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
            guard len >= 0, offset <= data.count - len else { return nil }
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

    static func moeInfo(at url: URL) -> MoEInfo? {
        var target = url
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir), isDir.boolValue {
            if let fallback = try? FileManager.default
                .contentsOfDirectory(at: target, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension.lowercased() == "gguf" }) {
                target = fallback
            }
        }

        var scan = gguf_moe_scan_result()
        let status = target.path.withCString { gguf_moe_scan($0, &scan) }
        if status == 0 && scan.status == 0 {
            let expertCount = max(Int(scan.expert_count), 0)
            let defaultUsed = scan.expert_used_count > 0 ? Int(scan.expert_used_count) : nil
            let moeLayers = scan.moe_layer_count > 0 ? Int(scan.moe_layer_count) : nil
            let totalLayers = scan.total_layer_count > 0 ? Int(scan.total_layer_count) : nil
            let hidden = scan.hidden_size > 0 ? Int(scan.hidden_size) : nil
            let feedForward = scan.feed_forward_size > 0 ? Int(scan.feed_forward_size) : nil
            let vocab = scan.vocab_size > 0 ? Int(scan.vocab_size) : nil

            return MoEInfo(
                isMoE: scan.is_moe != 0,
                expertCount: expertCount,
                defaultUsed: defaultUsed,
                moeLayerCount: moeLayers,
                totalLayerCount: totalLayers,
                hiddenSize: hidden,
                feedForwardSize: feedForward,
                vocabSize: vocab
            )
        }

        if let fallback = fallbackMoEInfo(at: target) {
            print("[MoEDetect] using Swift fallback scanner for \(target.lastPathComponent)")
            return fallback
        }

        print("[MoEDetect] MoE scan failed for \(target.lastPathComponent)")
        return nil
    }

    private static func fallbackMoEInfo(at url: URL) -> MoEInfo? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        var offset = 0

        func ensureCapacity(_ length: Int) -> Bool {
            if length < 0 { return false }
            return offset <= data.count - length
        }

        func readInteger<T: FixedWidthInteger>(_ type: T.Type) -> T? {
            let size = MemoryLayout<T>.size
            guard ensureCapacity(size) else { return nil }
            let value = data.subdata(in: offset..<offset+size).withUnsafeBytes { $0.load(as: T.self) }
            offset += size
            return T(littleEndian: value)
        }

        func readU8() -> UInt8? { readInteger(UInt8.self) }
        func readU16() -> UInt16? { readInteger(UInt16.self) }
        func readU32() -> UInt32? { readInteger(UInt32.self) }
        func readU64() -> UInt64? { readInteger(UInt64.self) }

        func readF32() -> Float? {
            guard let bits = readU32() else { return nil }
            return Float(bitPattern: bits)
        }

        func readF64() -> Double? {
            guard let bits = readU64() else { return nil }
            return Double(bitPattern: bits)
        }

        func roundedInt(from value: Double) -> Int? {
            guard value.isFinite else { return nil }
            let rounded = value.rounded()
            guard rounded >= Double(Int.min), rounded <= Double(Int.max) else { return nil }
            return Int(rounded)
        }

        func readString(len: Int) -> String? {
            guard ensureCapacity(len) else { return nil }
            let slice = data.subdata(in: offset..<offset+len)
            offset += len
            return String(data: slice, encoding: .utf8)
        }

        func skipBytes(_ count: Int) -> Bool {
            guard ensureCapacity(count) else { return false }
            offset += count
            return true
        }

        func readScalarInt(for type: UInt32) -> Int? {
            switch type {
            case 0: // uint8
                return readU8().map { Int($0) }
            case 1: // int8
                return readU8().map { Int(Int8(bitPattern: $0)) }
            case 2: // uint16
                return readU16().map { Int($0) }
            case 3: // int16
                return readU16().map { Int(Int16(bitPattern: $0)) }
            case 4: // uint32
                return readU32().flatMap { Int(exactly: $0) }
            case 5: // int32
                return readU32().map { Int(Int32(bitPattern: $0)) }
            case 6: // float32
                return readF32().flatMap { roundedInt(from: Double($0)) }
            case 7: // bool
                return readU8().map { $0 == 0 ? 0 : 1 }
            case 10: // uint64
                return readU64().flatMap { Int(exactly: $0) }
            case 11: // int64
                return readU64().map { Int(Int64(bitPattern: $0)) }
            case 12: // float64
                return readF64().flatMap { roundedInt(from: $0) }
            default:
                return nil
            }
        }

        func readArrayMaxInt(elementType: UInt32, count: UInt64) -> Int? {
            guard count <= UInt64(Int.max) else { return nil }
            var maxValue: Int?
            for _ in 0..<Int(count) {
                guard let value = readScalarInt(for: elementType) else { return nil }
                if let current = maxValue {
                    if value > current { maxValue = value }
                } else {
                    maxValue = value
                }
            }
            return maxValue
        }

        func readIntOrArrayMax(for type: UInt32) -> Int? {
            switch type {
            case 9: // array
                guard let elementType = readU32(), let count = readU64() else { return nil }
                return readArrayMaxInt(elementType: elementType, count: count)
            default:
                return readScalarInt(for: type)
            }
        }

        func isExpertCountKey(_ key: String) -> Bool {
            let lower = key.lowercased()
            return lower.hasSuffix("expert_count") || lower.contains("num_experts")
        }

        func isExpertUsedCountKey(_ key: String) -> Bool {
            let lower = key.lowercased()
            return lower.hasSuffix("expert_used_count") || lower.contains("active_experts")
        }

        func skipValue(ofType type: UInt32) -> Bool {
            switch type {
            case 0, 1, 7:
                return skipBytes(1)
            case 2, 3:
                return skipBytes(2)
            case 4, 5, 6:
                return skipBytes(4)
            case 10, 11, 12:
                return skipBytes(8)
            case 8:
                guard let len = readU64().map(Int.init) else { return false }
                return skipBytes(len)
            case 9:
                guard let elemType = readU32(), let count = readU64() else { return false }
                if elemType == 8 {
                    for _ in 0..<count {
                        guard let len = readU64().map(Int.init) else { return false }
                        guard skipBytes(len) else { return false }
                    }
                    return true
                }
                let elementSize: Int
                switch elemType {
                case 0, 1, 7: elementSize = 1
                case 2, 3: elementSize = 2
                case 4, 5, 6: elementSize = 4
                case 10, 11, 12: elementSize = 8
                default: elementSize = 4
                }
                guard elementSize > 0 else { return false }
                let maxElements = UInt64(Int.max) / UInt64(elementSize)
                guard count <= maxElements else { return false }
                return skipBytes(Int(count) * elementSize)
            default:
                return false
            }
        }

        func parseBlockIndex(from name: String) -> Int {
            guard name.hasPrefix("blk.") else { return -1 }
            let rest = name.dropFirst(4)
            var digits = ""
            for ch in rest {
                if ch.isNumber {
                    digits.append(ch)
                } else {
                    break
                }
            }
            return Int(digits) ?? -1
        }

        guard let magic = readString(len: 4), magic == "GGUF" else { return nil }
        guard readU32() != nil else { return nil } // version
        guard let tensorCount64 = readU64(), tensorCount64 <= UInt64(Int.max) else { return nil }
        guard let kvCount64 = readU64(), kvCount64 <= UInt64(Int.max) else { return nil }

        let tensorCount = Int(tensorCount64)
        let kvCount = Int(kvCount64)

        var isMoE = false
        var expertCount = 0
        var defaultUsed: Int?
        var moeLayerCount: Int?
        var totalLayerCount: Int?
        var hiddenSize: Int?
        var feedForwardSize: Int?
        var vocabSize: Int?
        var maxBlockIndex = -1

        for _ in 0..<kvCount {
            guard let keyLen = readU64().map(Int.init), let key = readString(len: keyLen), let type = readU32() else {
                return nil
            }
            var consumed = false

            switch key {
            case "llama.expert_count":
                if let value = readIntOrArrayMax(for: type) {
                    expertCount = max(expertCount, max(value, 0))
                    if value > 0 { isMoE = true }
                    consumed = true
                }
            case "llama.expert_used_count":
                if let value = readIntOrArrayMax(for: type), value > 0 {
                    defaultUsed = value
                    consumed = true
                }
            case "llama.block_count", "llama.n_layer", "hparams.n_layer":
                if let value = readScalarInt(for: type), value > 0 {
                    totalLayerCount = value
                    consumed = true
                }
            case "llama.embedding_length":
                if let value = readScalarInt(for: type), value > 0 {
                    hiddenSize = value
                    consumed = true
                }
            case "llama.feed_forward_length":
                if let value = readScalarInt(for: type), value > 0 {
                    feedForwardSize = value
                    consumed = true
                }
            case "llama.vocab_size":
                if let value = readScalarInt(for: type), value > 0 {
                    vocabSize = value
                    consumed = true
                }
            default:
                if isExpertCountKey(key) {
                    if let value = readIntOrArrayMax(for: type) {
                        expertCount = max(expertCount, max(value, 0))
                        if value > 0 { isMoE = true }
                        consumed = true
                    }
                } else if isExpertUsedCountKey(key) {
                    if let value = readIntOrArrayMax(for: type), value > 0 {
                        defaultUsed = value
                        consumed = true
                    }
                }
            }

            if !consumed {
                guard skipValue(ofType: type) else { return nil }
            }
        }

        var moeLayers = 0
        for _ in 0..<tensorCount {
            guard let nameLen = readU64().map(Int.init), let name = readString(len: nameLen) else { return nil }
            guard let dimCount = readU32().map(Int.init) else { return nil }
            for _ in 0..<dimCount {
                guard readU64() != nil else { return nil }
            }
            guard readU32() != nil else { return nil }
            guard readU64() != nil else { return nil }

            let blockIndex = parseBlockIndex(from: name)
            if blockIndex >= 0 && blockIndex > maxBlockIndex {
                maxBlockIndex = blockIndex
            }

            if name.hasSuffix(".ffn_gate_inp.weight") {
                moeLayers += 1
            }
        }

        if moeLayers > 0 {
            moeLayerCount = moeLayers
            isMoE = true
        }

        if totalLayerCount == nil && maxBlockIndex >= 0 {
            totalLayerCount = maxBlockIndex + 1
        }

        return MoEInfo(
            isMoE: isMoE,
            expertCount: expertCount,
            defaultUsed: defaultUsed,
            moeLayerCount: moeLayerCount,
            totalLayerCount: totalLayerCount,
            hiddenSize: hiddenSize,
            feedForwardSize: feedForwardSize,
            vocabSize: vocabSize
        )
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
