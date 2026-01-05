// ModelRAMAdvisor.swift
import SwiftUI

@_silgen_name("app_available_memory")
fileprivate func c_app_available_memory() -> UInt

enum ModelRAMAdvisor {
    /// Returns the current available bytes the app may allocate before hitting its limit.
    /// Uses os_proc_available_memory via C bridge. Returns nil if unavailable or zero.
    private static func availableMemoryBytes() -> Int64? {
        let v = Int64(c_app_available_memory())
        return v > 0 ? v : nil
    }
    /// Conservative multiplier from quant file size to approximate working set in RAM
    /// for weights and runtime overheads (not including KV cache which scales with context).
    /// Values vary per format; these are rough heuristics.
    private static func baseWeightsMultiplier(for format: ModelFormat) -> Double {
        switch format {
        case .gguf: return 1.3   // slightly more conservative
        case .mlx:  return 1.2   // slightly more conservative
        case .slm:  return 1.1   // slightly more conservative
        case .apple: return 1.0
        }
    }

    /// Approximate hidden size from known quant sizes when explicit metadata is unavailable.
    /// This is a heuristic to scale KV cache cost with model capacity.
    private static func approximateHiddenSize(format: ModelFormat, sizeBytes: Int64) -> Int {
        // Heuristic buckets derived from common Llama/Mistral quants
        let gb = Double(sizeBytes) / 1_073_741_824.0
        switch format {
        case .gguf:
            if gb < 3.0 { return 3072 }     // very small (e.g., 3B/4B)
            if gb < 6.0 { return 4096 }     // 7B class
            if gb < 12.0 { return 5120 }    // 13B class
            if gb < 24.0 { return 6656 }    // 30B class
            return 8192                      // 70B class and above
        case .mlx, .apple, .slm:
            // MLX/Apple/SLM models vary widely; use a modest default
            if gb < 3.0 { return 3072 }
            if gb < 6.0 { return 4096 }
            if gb < 12.0 { return 5120 }
            return 6144
        }
    }

    /// Estimate KV cache memory in bytes given context length and optional architecture hints.
    /// GQA-aware heuristic: KV size scales with num_kv_heads/num_attention_heads factor (typically 1/8 for Llama-2/3).
    /// Rough formula: 2 (K,V) * layers * context * hidden_size * bytes_per_element * gqa_factor.
    /// We assume F16 for KV by default (2 bytes/element) in our runner.
    private static func estimateKVBytes(format: ModelFormat, sizeBytes: Int64, contextLength: Int, layerCount: Int?) -> Int64 {
        let bytesPerElement = 2 // F16
        let layers = max(1, layerCount ?? 32)
        let hidden = approximateHiddenSize(format: format, sizeBytes: sizeBytes)
        // Typical GQA ratios:
        // - Llama 7B/8B: n_kv_head = n_head / 8
        // - Many 13B: n_kv_head = n_head / 8 or /4
        // - 70B: often /8
        // Without header parsing of n_head/n_kv_head, assume a safer 1/4 reduction for GGUF and 1/2 for others
        let gqaFactor: Double = {
            switch format {
            case .gguf: return 0.45 // more conservative KV estimate
            case .mlx, .apple, .slm: return 0.6
            }
        }()
        let kv = Int64(2) * Int64(layers) * Int64(max(1, contextLength)) * Int64(hidden) * Int64(bytesPerElement)
        return Int64(Double(kv) * gqaFactor)
    }

    private static func estimatedWeightBytes(format: ModelFormat, sizeBytes: Int64, moeInfo: MoEInfo?, layerCount: Int?) -> Int64 {
        let baseMultiplier = baseWeightsMultiplier(for: format)

        // Fallback to dense heuristic when we cannot confidently reason about MoE structure
        guard format == .gguf,
              let info = moeInfo,
              info.isMoE,
              let totalLayers = info.totalLayerCount ?? layerCount,
              totalLayers > 0 else {
            return Int64(Double(sizeBytes) * baseMultiplier)
        }

        // Dimensions and layer breakdown
        let expertCount = max(info.expertCount, 1)
        let activeExperts = min(max(info.defaultUsed ?? 2, 1), expertCount) // typical top-2 gating fallback
        let hiddenSize = info.hiddenSize ?? approximateHiddenSize(format: format, sizeBytes: sizeBytes)
        let feedForwardSize = info.feedForwardSize ?? hiddenSize * 4
        let moeLayers = max(info.moeLayerCount ?? totalLayers, 0)
        let denseLayers = max(totalLayers - moeLayers, 0)

        // Parameter accounting (very coarse but architecture-aware):
        // - Attention per layer ~ 4 * d * d (q,k,v,o projections)
        // - FFN (SwiGLU-style) per layer ~ 3 * d * f
        // - MoE FFN per layer ~ (#experts) * (3 * d * f)
        // - Embedding params ~ vocab * d (optional when available)
        let d = Double(hiddenSize)
        let f = Double(feedForwardSize)
        let L = Double(totalLayers)
        let coefficient = 3.0

        let attentionParams = L * 4.0 * d * d
        let denseFFNParams = Double(denseLayers) * coefficient * d * f
        let perExpertParams = coefficient * d * f
        let allMoEParams = Double(moeLayers) * Double(expertCount) * perExpertParams
        let embeddingParams = info.vocabSize.map { Double($0) * d } ?? 0.0

        // Total parameter count represented by the quant file (used to derive bytes/param)
        let totalParams = attentionParams + denseFFNParams + allMoEParams + embeddingParams
        guard totalParams > 0 else {
            return Int64(Double(sizeBytes) * baseMultiplier)
        }

        // Convert active parameter set into bytes using bytes-per-param implied by the quant file
        let bytesPerParam = Double(sizeBytes) / totalParams

        // Active MoE parameters: only a subset of experts are used per MoE layer at inference time
        let activeMoEParams = Double(moeLayers) * Double(activeExperts) * perExpertParams
        let activeParams = attentionParams + denseFFNParams + activeMoEParams + embeddingParams

        // Apply base multiplier to approximate runtime expansion/allocator overhead
        var weightsBytes = activeParams * bytesPerParam * baseMultiplier

        // Modest extra safety for MoE routing/gating buffers without double-counting global safety later
        let moeSafety: Double = 1.05
        weightsBytes *= moeSafety

        // Prevent overflow and return
        let clamped = max(0.0, min(weightsBytes, Double(Int64.max)))
        return Int64(clamped)
    }

    /// Whether a model of given format and size likely fits within the device RAM budget
    /// for a specific context length and (optional) layer count.
    static func fitsInRAM(format: ModelFormat, sizeBytes: Int64, contextLength: Int, layerCount: Int?, moeInfo: MoEInfo? = nil) -> Bool {
        let (estimate, conservativeBudget) = budgetAndEstimate(format: format, sizeBytes: sizeBytes, contextLength: contextLength, layerCount: layerCount, moeInfo: moeInfo)
        let liveAvailable = availableMemoryBytes()

#if os(macOS) || targetEnvironment(macCatalyst)
        if let conservativeBudget, let liveAvailable, liveAvailable > 0 {
            return estimate <= max(conservativeBudget, liveAvailable)
        }
        if let conservativeBudget {
            return estimate <= conservativeBudget
        }
        if let liveAvailable, liveAvailable > 0 {
            return estimate <= liveAvailable
        }
        // If no budget or availability information is present, default to permissive (legacy behavior)
        return true
#else
        if let liveAvailable, liveAvailable > 0 {
            if let conservativeBudget {
                return estimate <= min(conservativeBudget, liveAvailable)
            }
            return estimate <= liveAvailable
        }
        if let conservativeBudget {
            return estimate <= conservativeBudget
        }
        // If no budget information is available at all, default to permissive (legacy behavior)
        return true
#endif
    }

    /// Backwards-compatible overload (assumes a default context of 4096 and unknown layer count).
    static func fitsInRAM(format: ModelFormat, sizeBytes: Int64) -> Bool {
        return fitsInRAM(format: format, sizeBytes: sizeBytes, contextLength: 4096, layerCount: nil, moeInfo: nil)
    }

    /// Exposes the raw estimate and device budget for UI display.
    static func estimateAndBudget(format: ModelFormat, sizeBytes: Int64, contextLength: Int, layerCount: Int?, moeInfo: MoEInfo? = nil) -> (estimate: Int64, budget: Int64?) {
        return budgetAndEstimate(format: format, sizeBytes: sizeBytes, contextLength: contextLength, layerCount: layerCount, moeInfo: moeInfo)
    }

    /// Compute maximum context that fits under budget for this model on this device.
    /// Returns nil if no budget info is available.
    static func maxContextUnderBudget(format: ModelFormat, sizeBytes: Int64, layerCount: Int?, moeInfo: MoEInfo? = nil) -> Int? {
        let info = DeviceRAMInfo.current()
        guard let budget = info.conservativeLimitBytes() else { return nil }
        // Invert estimate: budget ≈ safety*(weights + kv(ctx)) + overhead
        let safety: Double = 1.10
        let overhead: Int64 = 200 * 1024 * 1024
        let weights = estimatedWeightBytes(format: format, sizeBytes: sizeBytes, moeInfo: moeInfo, layerCount: layerCount)
        let remaining = max(Int64(0), Int64(Double(budget) / safety) - (weights + overhead))
        if remaining <= 0 { return 512 }
        // Solve remaining ≈ kv(ctx)
        // kv(ctx) ≈ 2 * layers * ctx * hidden * 2B * gqa
        // So ctx ≈ remaining / (const)
        let hidden = approximateHiddenSize(format: format, sizeBytes: sizeBytes)
        let layers = max(1, layerCount ?? 32)
        let gqa: Double = (format == .gguf) ? 0.45 : 0.6
        let denom = Double(2 /*K,V*/ * layers * hidden * 2) * gqa
        if denom <= 0 { return 512 }
        let ctx = Int(Double(remaining) / denom)
        // Clamp to reasonable bounds
        return max(512, min(32768, ctx))
    }

    /// Returns (estimateWorkingSetBytes, budgetBytes)
    private static func budgetAndEstimate(format: ModelFormat, sizeBytes: Int64, contextLength: Int, layerCount: Int?, moeInfo: MoEInfo?) -> (Int64, Int64?) {
        let info = DeviceRAMInfo.current()
        let budgetBytes: Int64? = info.conservativeLimitBytes()
        // Weights + overheads
        let weights = estimatedWeightBytes(format: format, sizeBytes: sizeBytes, moeInfo: moeInfo, layerCount: layerCount)
        // KV cache scales roughly linearly with context
        let kv = estimateKVBytes(format: format, sizeBytes: sizeBytes, contextLength: contextLength, layerCount: layerCount)
        // Slightly higher fixed overhead to account for fragmentation and allocator slop
        let overhead: Int64 = 200 * 1024 * 1024
        // Add a small safety margin on top of all components
        let safetyFactor: Double = 1.10
        let estimate = Int64(Double(weights &+ kv &+ overhead) * safetyFactor)
        return (estimate, budgetBytes)
    }

    @ViewBuilder
    static func badge(format: ModelFormat, sizeBytes: Int64, contextLength: Int = 4096, layerCount: Int? = nil, moeInfo: MoEInfo? = nil) -> some View {
        let (estimate, budget) = budgetAndEstimate(format: format, sizeBytes: sizeBytes, contextLength: contextLength, layerCount: layerCount, moeInfo: moeInfo)
        let fits: Bool = {
            guard let budget else { return true }
            return estimate <= budget
        }()
        RAMBadgeView(fits: fits, estimate: estimate, budget: budget, context: contextLength)
    }
}

private struct RAMBadgeView: View {
    let fits: Bool
    let estimate: Int64
    let budget: Int64?
    let context: Int
    @State private var showInfo = false
    @Environment(\.locale) private var locale

    private var color: Color { fits ? .green : .red }
    private var symbol: String { fits ? "checkmark" : "xmark" }

    private func localizedMemoryString(_ bytes: Int64) -> String {
        let useGB = bytes >= 1_073_741_824
        let value = useGB ? Double(bytes) / 1_073_741_824.0 : Double(bytes) / 1_048_576.0
        let unit: UnitInformationStorage = useGB ? .gigabytes : .megabytes

        let formatter = MeasurementFormatter()
        formatter.locale = locale
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .medium
        formatter.numberFormatter.locale = locale
        formatter.numberFormatter.maximumFractionDigits = 1
        formatter.numberFormatter.minimumFractionDigits = 0
        return formatter.string(from: Measurement(value: value, unit: unit))
    }

    private var infoText: String {
        let estStr = localizedMemoryString(estimate)
        let budStr = budget.map { localizedMemoryString($0) } ?? "--"
        let ctxFormatter = NumberFormatter()
        ctxFormatter.locale = locale
        ctxFormatter.numberStyle = .decimal
        let ctx = ctxFormatter.string(from: NSNumber(value: context)) ?? "\(context)"
        return String.localizedStringWithFormat(
            String(localized: "Estimate: %@\nBudget: %@\nContext length: %@ tokens\n\nThis is an estimate based on your device’s memory budget, context length (KV cache), and typical runtime overheads. Actual usage may vary.", locale: locale),
            estStr, budStr, ctx
        )
    }

    var body: some View {
        Button(action: { showInfo = true }) {
            Image(systemName: symbol)
                .font(.caption2.weight(.bold))
                .foregroundColor(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(color.opacity(0.15))
                .clipShape(Capsule())
                .accessibilityLabel(fits ? LocalizedStringKey("Model likely fits in RAM") : LocalizedStringKey("Model may not fit in RAM"))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showInfo) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: symbol).foregroundColor(color)
                    Text(fits ? LocalizedStringKey("Fits in RAM (estimated)") : LocalizedStringKey("May not fit (estimated)"))
                        .font(.headline)
                }
                Text(infoText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(LocalizedStringKey("OK")) { showInfo = false }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(12)
            .presentationDetents([.fraction(0.25)])
            .presentationDragIndicator(.visible)
        }
    }
}
