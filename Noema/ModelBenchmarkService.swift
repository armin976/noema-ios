// ModelBenchmarkService.swift
import Foundation

@MainActor
protocol ModelBenchmarkingViewModel: AnyObject {
    var modelLoaded: Bool { get }
    var loadedModelURL: URL? { get }
    var loadedModelSettings: ModelSettings? { get }
    var loadedModelFormat: ModelFormat? { get }
    var loadError: String? { get }

    func load(
        url: URL,
        settings: ModelSettings?,
        format: ModelFormat?,
        forceReload: Bool
    ) async -> Bool

    func activeClientForBenchmark() throws -> AnyLLMClient
    func makeBenchmarkInput(from rawPrompt: String) -> LLMInput

    /// Called by the benchmark service to ensure any model it loaded
    /// is explicitly torn down after the benchmark finishes.
    func unloadAfterBenchmark() async
}

@_silgen_name("app_memory_footprint")
private func c_app_memory_footprint() -> UInt

enum ModelBenchmarkError: LocalizedError {
    case unsupportedFormat
    case weightsMissing
    case loadFailed(String)
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return String(localized: "Benchmarking is not available for this model format.")
        case .weightsMissing:
            return String(localized: "The selected model's weights could not be located.")
        case .loadFailed(let message):
            return String.localizedStringWithFormat(
                String(localized: "Failed to load model for benchmark: %@"),
                message
            )
        case .generationFailed(let message):
            return String.localizedStringWithFormat(
                String(localized: "Benchmark generation failed: %@"),
                message
            )
        }
    }
}

struct ModelBenchmarkResult: Identifiable {
    let id = UUID()
    let format: ModelFormat
    let settings: ModelSettings
    let kvCacheOffloadActive: Bool
    let promptTokens: Int
    let promptRate: Double
    let generationTokens: Int
    let generationRate: Double
    let totalDuration: TimeInterval
    let timeToFirstToken: TimeInterval
    let peakMemoryBytes: Int64
    let memoryDeltaBytes: Int64
    let outputPreview: String
    let completedAt: Date
}

struct ModelBenchmarkProgress {
    let fraction: Double
    let detail: String
}

private struct MainActorIsolated<Value>: @unchecked Sendable {
    let value: Value
}

enum ModelBenchmarkService {
    private static func log(_ message: String) {
        Task { await logger.log("[Benchmark] \(message)") }
    }

    private static func logError(_ message: String) {
        Task { await logger.log("[Benchmark][Error] \(message)") }
    }

    private static func describe(settings: ModelSettings) -> String {
        var pieces: [String] = []
        pieces.append("ctx=\(Int(settings.contextLength))")
        if settings.gpuLayers >= 0 { pieces.append("gpuLayers=\(settings.gpuLayers)") }
        if settings.cpuThreads > 0 { pieces.append("threads=\(settings.cpuThreads)") }
        pieces.append("kvOffload=\(settings.kvCacheOffload)")
        pieces.append("flash=\(settings.flashAttention)")
        if let seed = settings.seed { pieces.append("seed=\(seed)") }
        pieces.append(String(format: "temp=%.2f", settings.temperature))
        pieces.append(String(format: "topP=%.2f", settings.topP))
        pieces.append("topK=\(settings.topK)")
        return pieces.joined(separator: " ")
    }

    private static let prompt: String = {
        return "You are running a performance benchmark. Respond with a numbered list of 24 concise technology facts, each under ten words. Finish with a short summary sentence."
    }()

    static func run<VM: ModelBenchmarkingViewModel>(
        model: LocalModel,
        settings: ModelSettings,
        vm: VM,
        progress: (@MainActor (ModelBenchmarkProgress) -> Void)? = nil
    ) async throws -> ModelBenchmarkResult {
        let vmRef = MainActorIsolated(value: vm)
        let settingsSnapshot = settings
        let isLoaded = await MainActor.run { vmRef.value.modelLoaded }
        let loadedURL = await MainActor.run { vmRef.value.loadedModelURL }
        let loadedSettings = await MainActor.run { vmRef.value.loadedModelSettings }
        let loadedFormat = await MainActor.run { vmRef.value.loadedModelFormat }
        let urlMatches = loadedURL == Optional(model.url)
        let settingsMatch = loadedSettings == Optional(settings)
        let formatMatch = loadedFormat == Optional(model.format)
        let needsLoad = !(isLoaded && urlMatches && settingsMatch && formatMatch)

        // Track whether this run performed a load so we can clean up.
        var loadedForBenchmark = false
        defer {
            if loadedForBenchmark {
                // Fire-and-forget on the main actor; we don't want to block result delivery
                Task { @MainActor in
                    await vmRef.value.unloadAfterBenchmark()
                }
            }
        }

        if needsLoad {
            log("Model not loaded or settings changed – performing reload for benchmark")
        } else {
            log("Reusing existing loaded model for benchmark run")
        }

        log("Starting benchmark for model=\(model.name) format=\(model.format) settings=[\(describe(settings: settingsSnapshot))]")
        guard model.format != .apple else { throw ModelBenchmarkError.unsupportedFormat }

        try Task.checkCancellation()

        if needsLoad {
            let loadSucceeded = await vmRef.value.load(
                url: model.url,
                settings: settingsSnapshot,
                format: model.format,
                forceReload: true
            )
            if !loadSucceeded {
                let loadError = await MainActor.run { vmRef.value.loadError }
                let message = loadError ?? "Unknown load failure"
                logError("Benchmark load failed: \(message)")
                throw ModelBenchmarkError.loadFailed(message)
            }
            loadedForBenchmark = true
        } else {
            try Task.checkCancellation()
        }

        try Task.checkCancellation()

        let client: AnyLLMClient
        do {
            client = try await MainActor.run {
                try vmRef.value.activeClientForBenchmark()
            }
        } catch {
            logError("Benchmark client unavailable: \(error.localizedDescription)")
            throw ModelBenchmarkError.loadFailed(error.localizedDescription)
        }

        let input = await MainActor.run {
            vmRef.value.makeBenchmarkInput(from: prompt)
        }

        return try await executeBenchmark(
            with: client,
            input: input,
            settings: settingsSnapshot,
            format: model.format,
            progress: progress
        )
    }

    private static func executeBenchmark(
        with client: AnyLLMClient,
        input: LLMInput,
        settings: ModelSettings,
        format: ModelFormat,
        progress: (@MainActor (ModelBenchmarkProgress) -> Void)?
    ) async throws -> ModelBenchmarkResult {
        log("Benchmark run starting – promptTokens≈\(estimateTokens(for: prompt))")
        let startFootprint = Int64(c_app_memory_footprint())
        var peakFootprint = startFootprint
        let start = Date()
        var aggregate = ""
        var firstTokenDate: Date?
        var chunkCount = 0
        var lastProgressLog = Date()
        var lastUIUpdate = Date(timeIntervalSince1970: 0)
        let maxDuration: TimeInterval = 75
        let promptEstimate = estimateTokens(for: prompt)
        let generationCap = max(512, promptEstimate * 4)
        var hitDurationLimit = false
        var hitTokenLimit = false

        do {
            try Task.checkCancellation()
            let stream = try await client.textStream(from: input)
            await MainActor.run {
                progress?(ModelBenchmarkProgress(
                    fraction: 0.0,
                    detail: String(localized: "Streaming benchmark output…")
                ))
            }
            for try await chunk in stream {
                try Task.checkCancellation()
                if firstTokenDate == nil {
                    firstTokenDate = Date()
                    let delay = firstTokenDate!.timeIntervalSince(start)
                    log(String(format: "First token received after %.2fs", delay))
                }
                aggregate += chunk
                chunkCount += 1
                let now = Date()
                if now.timeIntervalSince(lastProgressLog) >= 2 {
                    let elapsed = now.timeIntervalSince(start)
                    log(String(format: "Stream progress: chunks=%d chars=%d elapsed=%.2fs", chunkCount, aggregate.count, elapsed))
                    lastProgressLog = now
                }
                if now.timeIntervalSince(lastUIUpdate) >= 0.5 {
                    let estTokens = estimateTokens(for: aggregate)
                    let fraction = min(1.0, Double(estTokens) / Double(generationCap))
                    let label = String.localizedStringWithFormat(
                        String(localized: "Streaming… %d chunks (~%d tok est.)"),
                        chunkCount,
                        estTokens
                    )
                    await MainActor.run {
                        progress?(ModelBenchmarkProgress(fraction: fraction, detail: label))
                    }
                    lastUIUpdate = now
                }
                let estTokens = estimateTokens(for: aggregate)
                if estTokens >= generationCap {
                    log("Benchmark token limit reached (est=\(estTokens), cap=\(generationCap)) – cancelling stream")
                    hitTokenLimit = true
                    client.cancelActive()
                    break
                }
                if now.timeIntervalSince(start) >= maxDuration {
                    log("Benchmark duration limit reached (\(maxDuration)s) – cancelling stream")
                    hitDurationLimit = true
                    client.cancelActive()
                    break
                }
                let current = Int64(c_app_memory_footprint())
                if current > peakFootprint {
                    peakFootprint = current
                }
            }
        } catch is CancellationError {
            log("Benchmark cancelled during streaming")
            throw CancellationError()
        } catch {
            logError("Benchmark streaming failed: \(error.localizedDescription)")
            throw ModelBenchmarkError.generationFailed(error.localizedDescription)
        }

        let end = Date()
        await MainActor.run {
            progress?(ModelBenchmarkProgress(fraction: 1.0, detail: "Finalizing results…"))
        }
        if aggregate.isEmpty {
            aggregate = "(no output)"
            log("Benchmark completed with no output from the model")
        } else {
            log(String(format: "Benchmark completed – produced %d chars across %d chunks", aggregate.count, chunkCount))
        }
        let totalDuration = end.timeIntervalSince(start)
        let timeToFirst = firstTokenDate?.timeIntervalSince(start) ?? totalDuration
        let generationDuration = max(0, totalDuration - timeToFirst)

        let promptTokens = estimateTokens(for: prompt)
        let generationTokens = estimateTokens(for: aggregate)
        let promptRate = timeToFirst > 0 ? Double(promptTokens) / timeToFirst : 0
        let generationRate = generationDuration > 0 ? Double(generationTokens) / generationDuration : 0

        let finalFootprint = Int64(c_app_memory_footprint())
        peakFootprint = max(peakFootprint, finalFootprint)
        let delta = max(Int64(0), peakFootprint - startFootprint)

        log(String(format: "Durations: total=%.2fs ttf=%.2fs gen=%.2fs", totalDuration, timeToFirst, generationDuration))
        log("Token estimates: prompt=\(promptTokens) (~\(String(format: "%.2f", promptRate)) t/s) generation=\(generationTokens) (~\(String(format: "%.2f", generationRate)) t/s)")
        log("Memory: start=\(startFootprint)B peak=\(peakFootprint)B delta=\(delta)B")
        if hitTokenLimit {
            log("Benchmark ended after hitting the token cap")
        }
        if hitDurationLimit {
            log("Benchmark ended after hitting the time limit")
        }

        return ModelBenchmarkResult(
            format: format,
            settings: settings,
            kvCacheOffloadActive: kvOffloadEnabled(for: settings),
            promptTokens: promptTokens,
            promptRate: promptRate,
            generationTokens: generationTokens,
            generationRate: generationRate,
            totalDuration: totalDuration,
            timeToFirstToken: timeToFirst,
            peakMemoryBytes: peakFootprint,
            memoryDeltaBytes: delta,
            outputPreview: String(aggregate.prefix(400)),
            completedAt: Date()
        )
    }

    private static func estimateTokens(for text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        let charEstimate = max(1, trimmed.count / 4)
        let wordEstimate = max(1, trimmed.split { $0.isWhitespace || $0.isNewline }.count * 3 / 2)
        return max(charEstimate, wordEstimate)
    }

    private static func kvOffloadEnabled(for settings: ModelSettings) -> Bool {
        let supportsOffload = DeviceGPUInfo.supportsGPUOffload
        guard supportsOffload else { return false }
        let resolvedGpuLayers: Int = {
            if settings.gpuLayers < 0 { return 1_000_000 }
            return max(0, settings.gpuLayers)
        }()
        return resolvedGpuLayers > 0 && settings.kvCacheOffload
    }
}
