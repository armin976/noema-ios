import Foundation

/// High-level hardware capability tiers derived from local device characteristics.
enum DeviceTier: String, CaseIterable, Identifiable {
    case limited
    case standard
    case advanced
    case flagship

    var id: String { rawValue }

    fileprivate var rank: Int {
        switch self {
        case .limited: return 0
        case .standard: return 1
        case .advanced: return 2
        case .flagship: return 3
        }
    }

    var displayName: String {
        switch self {
        case .limited: return "Limited"
        case .standard: return "Standard"
        case .advanced: return "Advanced"
        case .flagship: return "Flagship"
        }
    }
}

struct ModelPreset: Identifiable, Hashable {
    let id: String
    let tier: DeviceTier
    let title: String
    let subtitle: String
    let quantization: String
    let contextTokens: Int
    let estimatedInstallSeconds: Int

    var etaDescription: String {
        if estimatedInstallSeconds <= 75 {
            return "≈\(estimatedInstallSeconds) sec"
        }
        let minutes = Double(estimatedInstallSeconds) / 60.0
        return "≈\(String(format: "%.0f", ceil(minutes))) min"
    }
}

enum ModelPresets {
    static func allPresets() -> [ModelPreset] {
        return basePresets
    }

    static func presetsSorted() -> [ModelPreset] {
        basePresets.sorted { lhs, rhs in
            lhs.tier.rank == rhs.tier.rank ? lhs.contextTokens < rhs.contextTokens : lhs.tier.rank < rhs.tier.rank
        }
    }

    static func recommendedPreset() -> ModelPreset {
        let tier = currentDeviceTier()
        return preset(for: tier)
    }

    static func preset(for tier: DeviceTier) -> ModelPreset {
        let matches = basePresets.filter { $0.tier == tier }
        if let first = matches.first { return first }
        return basePresets.first ?? fallbackPreset
    }

    static func nextSmallerPreset(relativeTo preset: ModelPreset) -> ModelPreset? {
        let sorted = presetsSorted()
        guard let index = sorted.firstIndex(of: preset), index > 0 else { return nil }
        return sorted[sorted.index(before: index)]
    }

    static func currentDeviceTier(ramInfo: DeviceRAMInfo = .current(), supportsGPU: Bool = DeviceGPUInfo.supportsGPUOffload) -> DeviceTier {
        let conservativeBytes = ramInfo.conservativeLimitBytes() ?? 0
        let oneGiB = Int64(1024 * 1024 * 1024)
        if conservativeBytes == 0 {
            return supportsGPU ? .standard : .limited
        }
        if conservativeBytes < oneGiB * 3 {
            return .limited
        } else if conservativeBytes < oneGiB * 5 {
            return supportsGPU ? .standard : .limited
        } else if conservativeBytes < oneGiB * 7 {
            return supportsGPU ? .advanced : .standard
        } else {
            return supportsGPU ? .flagship : .advanced
        }
    }

    static func contextLength(for tier: DeviceTier) -> Int {
        switch tier {
        case .limited: return 2048
        case .standard: return 4096
        case .advanced: return 6144
        case .flagship: return 8192
        }
    }

    private static let fallbackPreset = ModelPreset(
        id: "default",
        tier: .standard,
        title: "Balanced",
        subtitle: "Good quality and speed",
        quantization: "Q5_K",
        contextTokens: 4096,
        estimatedInstallSeconds: 420
    )

    private static let basePresets: [ModelPreset] = [
        ModelPreset(
            id: "limited.q4",
            tier: .limited,
            title: "Compact",
            subtitle: "Fits older phones",
            quantization: "Q4_K_M",
            contextTokens: 2048,
            estimatedInstallSeconds: 240
        ),
        ModelPreset(
            id: "standard.q5",
            tier: .standard,
            title: "Balanced",
            subtitle: "Quality + speed",
            quantization: "Q5_K",
            contextTokens: 4096,
            estimatedInstallSeconds: 420
        ),
        ModelPreset(
            id: "advanced.q6",
            tier: .advanced,
            title: "Clever",
            subtitle: "For recent Pro devices",
            quantization: "Q6_K",
            contextTokens: 6144,
            estimatedInstallSeconds: 660
        ),
        ModelPreset(
            id: "flagship.f16",
            tier: .flagship,
            title: "Best quality",
            subtitle: "Max context & quality",
            quantization: "F16",
            contextTokens: 8192,
            estimatedInstallSeconds: 840
        )
    ]
}
