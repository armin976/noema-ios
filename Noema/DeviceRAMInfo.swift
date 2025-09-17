// DeviceRAMInfo.swift
import Foundation

struct DeviceRAMInfo {
    let modelIdentifier: String
    let modelName: String
    let ram: String
    let limit: String
    let limitBytes: Int64?

    /// Returns a per-app memory budget in bytes by subtracting 512 MiB
    /// from the detected limit, never going below zero. If `limitBytes` is unavailable,
    /// this parses the human-readable `limit` string. This is used for fit predictions.
    func conservativeLimitBytes() -> Int64? {
        let oneGiB: Int64 = 1024 * 1024 * 1024
        let reserve: Int64 = 512 * 1024 * 1024
        // Prefer explicit byte value if present
        if let b = limitBytes {
            return max(0, b - reserve)
        }
        // Fallback: parse from human-readable string like "~7 GB"
        let s = limit.replacingOccurrences(of: "~", with: "").lowercased()
        let digits = s.components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted).joined()
        guard let val = Double(digits) else { return nil }
        let parsed: Int64
        if s.contains("gb") {
            parsed = Int64(val * Double(oneGiB))
        } else if s.contains("mb") {
            parsed = Int64(val * 1024 * 1024)
        } else {
            parsed = Int64(val * Double(oneGiB))
        }
        return max(0, parsed - reserve)
    }

    static func current() -> DeviceRAMInfo {
        let identifier = Self.hardwareIdentifier()
        if let entry = mapping[identifier] {
            return DeviceRAMInfo(modelIdentifier: identifier, modelName: entry.name, ram: entry.ram, limit: entry.limit, limitBytes: entry.limitBytes)
        } else {
            let name = "Unknown (model: \(identifier))"
            return DeviceRAMInfo(modelIdentifier: identifier, modelName: name, ram: "Unknown RAM", limit: "--", limitBytes: nil)
        }
    }

    private static func hardwareIdentifier() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { ptr in
                String(cString: ptr)
            }
        }
        return machine
    }

    private static let mapping: [String: (name: String, ram: String, limit: String, limitBytes: Int64?)] = [
        // iPhone X / XS / XR
        "iPhone10,3": ("iPhone X", "3–4 GB", "~2.5 GB", Int64(2500) * Int64(1024) * Int64(1024)),
        "iPhone10,6": ("iPhone X", "3–4 GB", "~2.5 GB", nil),
        "iPhone11,2": ("iPhone XS", "3–4 GB", "~2.5 GB", nil),
        "iPhone11,4": ("iPhone XS Max", "3–4 GB", "~2.5 GB", nil),
        "iPhone11,6": ("iPhone XS Max", "3–4 GB", "~2.5 GB", nil),
        "iPhone11,8": ("iPhone XR", "3–4 GB", "~2.5 GB", nil),

        // iPhone 11 & 12 series (non Pro)
        "iPhone12,1": ("iPhone 11", "4 GB", "~3 GB", nil),
        "iPhone12,3": ("iPhone 11 Pro", "4 GB", "~3 GB", nil),
        "iPhone12,5": ("iPhone 11 Pro Max", "4 GB", "~3 GB", nil),
        "iPhone13,1": ("iPhone 12 mini", "4 GB", "~3 GB", nil),
        "iPhone13,2": ("iPhone 12", "4 GB", "~3 GB", nil),

        // iPhone 12 Pro & later Pro models with 6 GB RAM
        "iPhone13,3": ("iPhone 12 Pro", "6 GB", "~5 GB", nil),
        "iPhone13,4": ("iPhone 12 Pro Max", "6 GB", "~5 GB", nil),
        "iPhone14,2": ("iPhone 13 Pro", "6 GB", "~5 GB", nil),
        "iPhone14,3": ("iPhone 13 Pro Max", "6 GB", "~5 GB", nil),
        "iPhone14,4": ("iPhone 13 mini", "4 GB", "~3 GB", nil),
        "iPhone14,5": ("iPhone 13", "4 GB", "~3 GB", nil),
        "iPhone14,7": ("iPhone 14", "6 GB", "~5 GB", nil),
        "iPhone14,8": ("iPhone 14 Plus", "6 GB", "~5 GB", nil),
        "iPhone15,2": ("iPhone 14 Pro", "6 GB", "~5 GB", nil),
        "iPhone15,3": ("iPhone 14 Pro Max", "6 GB", "~5 GB", nil),
        "iPhone15,4": ("iPhone 15", "6 GB", "~5 GB", nil),
        "iPhone15,5": ("iPhone 15 Plus", "6 GB", "~5 GB", nil),

        // 8 GB RAM devices
        "iPhone16,1": ("iPhone 15 Pro", "8 GB", "~7 GB", nil),
        "iPhone16,2": ("iPhone 15 Pro Max", "8 GB", "~7 GB", nil),
        "iPhone17,3": ("iPhone 16", "8 GB", "~7 GB", nil),
        "iPhone17,4": ("iPhone 16 Plus", "8 GB", "~7 GB", nil),
        "iPhone17,1": ("iPhone 16 Pro", "8 GB", "~7 GB", nil),
        "iPhone17,2": ("iPhone 16 Pro Max", "8 GB", "~7 GB", nil),
        "iPhone17,5": ("iPhone 16e", "8 GB", "~7 GB", Int64(7000) * Int64(1024) * Int64(1024)),
        
        // iPads that support iOS 17+ (starting from iPad Pro 2nd gen and newer)
        // iPad Pro 11" (all generations)
        "iPad8,1": ("iPad Pro 11\" (1st gen)", "4 GB", "~3 GB", nil),
        "iPad8,2": ("iPad Pro 11\" (1st gen)", "4 GB", "~3 GB", nil),
        "iPad8,3": ("iPad Pro 11\" (1st gen)", "6 GB", "~5 GB", nil),
        "iPad8,4": ("iPad Pro 11\" (1st gen)", "6 GB", "~5 GB", nil),
        "iPad8,9": ("iPad Pro 11\" (2nd gen)", "6 GB", "~5 GB", nil),
        "iPad8,10": ("iPad Pro 11\" (2nd gen)", "6 GB", "~5 GB", nil),
        "iPad13,4": ("iPad Pro 11\" (3rd gen)", "8 GB", "~7 GB", nil),
        "iPad13,5": ("iPad Pro 11\" (3rd gen)", "8 GB", "~7 GB", nil),
        "iPad13,6": ("iPad Pro 11\" (3rd gen)", "8 GB", "~7 GB", nil),
        "iPad13,7": ("iPad Pro 11\" (3rd gen)", "8 GB", "~7 GB", nil),
        "iPad14,3": ("iPad Pro 11\" (4th gen)", "8 GB", "~7 GB", nil),
        "iPad14,4": ("iPad Pro 11\" (4th gen)", "8 GB", "~7 GB", nil),
        
        // iPad Pro 12.9" (3rd gen and newer support iOS 17+)
        "iPad8,5": ("iPad Pro 12.9\" (3rd gen)", "4 GB", "~3 GB", nil),
        "iPad8,6": ("iPad Pro 12.9\" (3rd gen)", "4 GB", "~3 GB", nil),
        "iPad8,7": ("iPad Pro 12.9\" (3rd gen)", "6 GB", "~5 GB", nil),
        "iPad8,8": ("iPad Pro 12.9\" (3rd gen)", "6 GB", "~5 GB", nil),
        "iPad8,11": ("iPad Pro 12.9\" (4th gen)", "6 GB", "~5 GB", nil),
        "iPad8,12": ("iPad Pro 12.9\" (4th gen)", "6 GB", "~5 GB", nil),
        "iPad13,8": ("iPad Pro 12.9\" (5th gen)", "8 GB", "~7 GB", nil),
        "iPad13,9": ("iPad Pro 12.9\" (5th gen)", "8 GB", "~7 GB", nil),
        "iPad13,10": ("iPad Pro 12.9\" (5th gen)", "16 GB", "~15 GB", nil),
        "iPad13,11": ("iPad Pro 12.9\" (5th gen)", "16 GB", "~15 GB", nil),
        "iPad14,5": ("iPad Pro 12.9\" (6th gen)", "8 GB", "~7 GB", nil),
        "iPad14,6": ("iPad Pro 12.9\" (6th gen)", "8 GB", "~7 GB", nil),
        
        // iPad Air (3rd gen and newer)
        "iPad11,3": ("iPad Air (3rd gen)", "3 GB", "~2.5 GB", nil),
        "iPad11,4": ("iPad Air (3rd gen)", "3 GB", "~2.5 GB", nil),
        "iPad13,1": ("iPad Air (4th gen)", "4 GB", "~3 GB", nil),
        "iPad13,2": ("iPad Air (4th gen)", "4 GB", "~3 GB", nil),
        "iPad13,16": ("iPad Air (5th gen)", "8 GB", "~7 GB", nil),
        "iPad13,17": ("iPad Air (5th gen)", "8 GB", "~7 GB", nil),
        "iPad14,8": ("iPad Air 11\" (6th gen)", "8 GB", "~7 GB", nil),
        "iPad14,9": ("iPad Air 11\" (6th gen)", "8 GB", "~7 GB", nil),
        "iPad14,10": ("iPad Air 13\" (6th gen)", "8 GB", "~7 GB", nil),
        "iPad14,11": ("iPad Air 13\" (6th gen)", "8 GB", "~7 GB", nil),
        
        // iPad (7th gen and newer)
        "iPad7,11": ("iPad (7th gen)", "3 GB", "~2.5 GB", nil),
        "iPad7,12": ("iPad (7th gen)", "3 GB", "~2.5 GB", nil),
        "iPad11,6": ("iPad (8th gen)", "3 GB", "~2.5 GB", nil),
        "iPad11,7": ("iPad (8th gen)", "3 GB", "~2.5 GB", nil),
        "iPad12,1": ("iPad (9th gen)", "3 GB", "~2.5 GB", nil),
        "iPad12,2": ("iPad (9th gen)", "3 GB", "~2.5 GB", nil),
        "iPad13,18": ("iPad (10th gen)", "4 GB", "~3 GB", nil),
        "iPad13,19": ("iPad (10th gen)", "4 GB", "~3 GB", nil),
        
        // iPad mini (5th gen and newer)
        "iPad11,1": ("iPad mini (5th gen)", "3 GB", "~2.5 GB", nil),
        "iPad11,2": ("iPad mini (5th gen)", "3 GB", "~2.5 GB", nil),
        "iPad14,1": ("iPad mini (6th gen)", "4 GB", "~3 GB", nil),
        "iPad14,2": ("iPad mini (6th gen)", "4 GB", "~3 GB", nil)
    ]
}
