import Foundation
import NoemaPackages

enum LoopbackStartupPlanner {
    struct RetryPlan {
        let settings: ModelSettings
        let configuration: LlamaServerBridge.StartConfiguration
        let reason: String
        let droppedTemplateOverride: Bool
    }

    static func makeRetryPlan(modelURL: URL,
                              requestedSettings: ModelSettings,
                              mmprojPath: String?,
                              diagnostics: LlamaServerBridge.StartDiagnostics?) -> RetryPlan {
        let settings = conservativeSettings(modelURL: modelURL, requestedSettings: requestedSettings)
        let droppedTemplateOverride = shouldDropTemplateOverride(diagnostics)
        let configuration: LlamaServerBridge.StartConfiguration
        if droppedTemplateOverride {
            configuration = LlamaServerBridge.StartConfiguration(
                ggufPath: modelURL.path,
                mmprojPath: mmprojPath
            )
        } else {
            configuration = TemplateDrivenModelSupport.loopbackStartConfiguration(
                modelURL: modelURL,
                ggufPath: modelURL.path,
                mmprojPath: mmprojPath
            )
        }

        return RetryPlan(
            settings: settings,
            configuration: configuration,
            reason: droppedTemplateOverride ? "template-reset" : "safe-settings",
            droppedTemplateOverride: droppedTemplateOverride
        )
    }

    static func conservativeSettings(modelURL: URL,
                                     requestedSettings: ModelSettings,
                                     budgetBytesOverride: Int64? = nil) -> ModelSettings {
        var recovered = requestedSettings
        let sizeBytes = (try? FileManager.default.attributesOfItem(atPath: modelURL.path)[.size]) as? Int64
        let layerCount = GGUFMetadata.layerCount(at: modelURL)
        let requestedContext = max(1, Int(requestedSettings.contextLength.rounded()))
        let maxModelContext = GGUFMetadata.contextLength(at: modelURL) ?? Int.max
        let kvCacheEstimate = ModelRAMAdvisor.GGUFKVCacheEstimate.resolved(from: requestedSettings)
        let safeBudgetContext = sizeBytes.map {
            ModelRAMAdvisor.maxContextUnderBudget(
                format: .gguf,
                sizeBytes: $0,
                layerCount: layerCount,
                moeInfo: nil,
                upperBound: maxModelContext == Int.max ? nil : maxModelContext,
                kvCacheEstimate: kvCacheEstimate,
                budgetBytesOverride: budgetBytesOverride
            )
        } ?? nil
        let fallbackSafeContext = safeBudgetContext ?? 4096
        recovered.contextLength = Double(max(1, min(requestedContext, maxModelContext, fallbackSafeContext)))
        recovered.gpuLayers = 0
        recovered.kvCacheOffload = false
        recovered.flashAttention = false
        recovered.disableWarmup = true
        recovered.useMmap = true
        let threads = requestedSettings.cpuThreads > 0
            ? requestedSettings.cpuThreads
            : ProcessInfo.processInfo.activeProcessorCount
        recovered.cpuThreads = max(1, threads)
        return recovered
    }

    static func shouldDropTemplateOverride(_ diagnostics: LlamaServerBridge.StartDiagnostics?) -> Bool {
        guard let diagnostics else { return false }
        let haystack = "\(diagnostics.code) \(diagnostics.message)".lowercased()
        return haystack.contains("chat template")
            || haystack.contains("jinja")
            || haystack.contains("reasoning")
    }

    static func formatFailureMessage(_ diagnostics: LlamaServerBridge.StartDiagnostics?,
                                     retryAttempted: Bool) -> String {
        let reason = diagnostics?.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? diagnostics!.message
            : (diagnostics?.code ?? "startup_failed")
        let status = diagnostics?.lastHTTPStatus.map(String.init) ?? "n/a"
        let progress = Int(round((diagnostics?.progress ?? 0) * 100))
        let retry = retryAttempted ? "attempted" : "not attempted"
        return [
            "Failed to start local GGUF runtime.",
            "Reason: \(reason)",
            "Status: \(status), progress: \(progress)%, retry: \(retry)",
            "Try lowering context length or resetting this model's settings."
        ].joined(separator: "\n")
    }

    static func summary(for settings: ModelSettings) -> String {
        let context = Int(settings.contextLength.rounded())
        return "ctx=\(context) gpu=\(settings.gpuLayers) kvOffload=\(settings.kvCacheOffload) flash=\(settings.flashAttention) warmupDisabled=\(settings.disableWarmup) mmap=\(settings.useMmap) threads=\(settings.cpuThreads)"
    }
}
