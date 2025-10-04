// ModelLoadingProgressTracker.swift
import Foundation
import SwiftUI

/// Tracks model loading progress with realistic phases
@MainActor
final class ModelLoadingProgressTracker: ObservableObject {
    enum LoadingPhase: Int, CaseIterable, Sendable {
        case initializing
        case loadingFile
        case loadingKernels
        case creatingContext
        case finalizing
        case complete

        static var allCases: [LoadingPhase] {
            [.initializing, .loadingFile, .loadingKernels, .creatingContext, .finalizing]
        }

        var label: String {
            switch self {
            case .initializing: return "Initializing..."
            case .loadingFile: return "Loading model file..."
            case .loadingKernels: return "Loading Metal kernels..."
            case .creatingContext: return "Creating context..."
            case .finalizing: return "Finalizing..."
            case .complete: return "Ready"
            }
        }

        var targetProgress: Double {
            switch self {
            case .initializing: return 0.05
            case .loadingFile: return 0.35
            case .loadingKernels: return 0.65
            case .creatingContext: return 0.85
            case .finalizing: return 0.95
            case .complete: return 1.0
            }
        }

        var speedMultiplier: Double {
            switch self {
            case .initializing: return 1.5
            case .loadingFile: return 1.0
            case .loadingKernels: return 0.6  // Slower for kernel loading
            case .creatingContext: return 0.4 // Even slower for context
            case .finalizing: return 0.8
            case .complete: return 2.0
            }
        }

        var orderIndex: Int {
            switch self {
            case .initializing: return 0
            case .loadingFile: return 1
            case .loadingKernels: return 2
            case .creatingContext: return 3
            case .finalizing: return 4
            case .complete: return 5
            }
        }
    }

    @Published var currentPhase: LoadingPhase = .initializing
    @Published var progress: Double = 0.0
    @Published var phaseLabel: String = LoadingPhase.initializing.label
    @Published var isLoading: Bool = false

    private var timer: Timer?
    private var targetProgress: Double = 0.0
    // Expose format for UI (read-only)
    private(set) var loadingFormat: ModelFormat = .gguf

    private var useLogDrivenProgress = false
    private var logObserver: NSObjectProtocol?
    private var metadataLogged = false
    private var backendLogged = false
    private var contextLogged = false
    private var finalizingLogged = false
    private var fallbackPhaseWorkItems: [LoadingPhase: DispatchWorkItem] = [:]
    private let maxLogLabelLength = 80

    init() {
        logObserver = NotificationCenter.default.addObserver(
            forName: .llamaLogMessage,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard
                let message = note.userInfo?["message"] as? String,
                !message.isEmpty
            else { return }

            self?.handleLlamaLogMessage(message)
        }
    }

    @MainActor deinit {
        timer?.invalidate()
        if let observer = logObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        cancelFallbacks()
    }

    func startLoading(for format: ModelFormat) {
        isLoading = true
        loadingFormat = format
        useLogDrivenProgress = (format == .gguf)
        clearLogFlags()
        cancelFallbacks()

        currentPhase = .initializing
        progress = 0.0
        phaseLabel = currentPhase.label
        targetProgress = currentPhase.targetProgress
        Task { await logger.log("[Progress] startLoading format=\(format) phase=\(currentPhase)") }

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateProgress()
            }
        }

        schedulePhaseTransitions()
    }

    func completeLoading() {
        useLogDrivenProgress = false
        cancelFallbacks()
        currentPhase = .complete
        phaseLabel = currentPhase.label
        targetProgress = 1.0
        Task { await logger.log("[Progress] completeLoading triggered") }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.timer?.invalidate()
            self.timer = nil
            self.progress = 1.0
            self.isLoading = false
            self.clearLogFlags()
            Task { await logger.log("[Progress] load animation finished progress=1.0") }
        }
    }

    private func updateProgress() {
        guard isLoading else { return }

        let speedMultiplier = currentPhase.speedMultiplier
        let baseIncrement = 0.002
        let increment = baseIncrement * speedMultiplier

        // Smooth progress towards target with easing
        let difference = targetProgress - progress
        if difference > 0 {
            // Use easing function to slow down as we approach target
            let easedIncrement = increment * (1 + difference * 2)
            progress = min(progress + easedIncrement, targetProgress)
        }

        // Add some random variation to make it feel more realistic
        if Double.random(in: 0...1) < 0.3 {
            progress = min(progress + Double.random(in: -0.001...0.002), targetProgress)
        }
    }

    private func schedulePhaseTransitions() {
        if useLogDrivenProgress {
            scheduleLogFallbacks()
            return
        }

        // Different timing for different model formats
        let timings: [(phase: LoadingPhase, delay: Double)] = loadingFormat == .mlx ? [
            (.loadingFile, 0.5),
            (.creatingContext, 2.0),  // MLX doesn't have kernel loading phase
            (.finalizing, 3.5)
        ] : [
            (.loadingFile, 0.5),
            (.loadingKernels, 2.0),   // GGUF has kernel loading
            (.creatingContext, 4.0),
            (.finalizing, 5.5)
        ]

        for (phase, delay) in timings {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.isLoading else { return }
                self.transitionToPhase(phase)
            }
        }
    }

    private func scheduleLogFallbacks() {
        let timings: [(phase: LoadingPhase, delay: Double)] = [
            (.loadingFile, 1.5),
            (.loadingKernels, 4.0),
            (.creatingContext, 8.0),
            (.finalizing, 11.0)
        ]

        for (phase, delay) in timings {
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.isLoading else { return }
                self.advance(to: phase, minProgress: phase.targetProgress, label: phase.label, fromFallback: true)
            }
            fallbackPhaseWorkItems[phase] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private func transitionToPhase(_ phase: LoadingPhase) {
        currentPhase = phase
        phaseLabel = phase.label
        targetProgress = max(targetProgress, phase.targetProgress)
        Task { await logger.log("[Progress] phase=\(phase) target=\(String(format: "%.2f", targetProgress))") }
    }

    private func advance(to phase: LoadingPhase, minProgress: Double, label: String, fromFallback: Bool = false) {
        guard isLoading else { return }

        let newIndex = phase.orderIndex
        let currentIndex = currentPhase.orderIndex

        if newIndex > currentIndex {
            currentPhase = phase
        } else if newIndex < currentIndex {
            cancelFallbacks(upTo: phase)
            return
        }

        if !fromFallback || phaseLabel == currentPhase.label {
            phaseLabel = label
        }

        targetProgress = max(targetProgress, minProgress)
        if progress < minProgress * 0.9 {
            progress = min(minProgress * 0.9, targetProgress)
        }

        cancelFallbacks(upTo: phase)

        if !fromFallback {
            Task { await logger.log("[Progress][log] phase=\(phase) label=\(label)") }
        }
    }

    private func handleLlamaLogMessage(_ message: String) {
        guard useLogDrivenProgress,
              isLoading,
              loadingFormat == .gguf else { return }
        processLogMessage(message)
    }

    private func processLogMessage(_ rawMessage: String) {
        let trimmed = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let lower = trimmed.lowercased()

        if !metadataLogged,
           (lower.contains("loading model from") || lower.contains("loaded meta data")) {
            metadataLogged = true
            advance(to: .loadingFile, minProgress: 0.25, label: "Reading GGUF metadata…")
            return
        }

        if !backendLogged {
            if lower.contains("ggml_metal") {
                backendLogged = true
                advance(to: .loadingKernels, minProgress: 0.55, label: "Preparing Metal kernels…")
                return
            }
            if lower.contains("ggml_cuda") || lower.contains("cuda backend") {
                backendLogged = true
                advance(to: .loadingKernels, minProgress: 0.55, label: "Preparing CUDA backend…")
                return
            }
            if lower.contains("ggml_vulkan") || lower.contains("ggml_opencl") || lower.contains("ggml_sycl") {
                backendLogged = true
                advance(to: .loadingKernels, minProgress: 0.55, label: "Preparing GPU backend…")
                return
            }
            if lower.contains("ggml_cpu") && lower.contains("init") {
                backendLogged = true
                advance(to: .loadingKernels, minProgress: 0.5, label: "Optimizing CPU backend…")
                return
            }
        }

        if !contextLogged,
           (lower.contains("llama_new_context_with_model") || lower.contains("kv cache") || lower.contains("llama_init_from_model") || lower.contains("ggml ctx")) {
            contextLogged = true
            let contextLabel = makeContextLabel(from: trimmed)
            advance(to: .creatingContext, minProgress: 0.8, label: contextLabel)
            return
        }

        if !finalizingLogged,
           (lower.contains("sampler") || lower.contains("warming up") || lower.contains("system info") || lower.contains("model load time") || lower.contains("llama_model_loader: done")) {
            finalizingLogged = true
            advance(to: .finalizing, minProgress: 0.92, label: "Finalizing setup…")
            return
        }
    }

    private func makeContextLabel(from message: String) -> String {
        if let range = message.range(of: "n_ctx") {
            let snippet = message[range.lowerBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !snippet.isEmpty {
                let truncated = snippet.count > maxLogLabelLength ? String(snippet.prefix(maxLogLabelLength)) + "…" : snippet
                return "Creating context (\(truncated))"
            }
        }
        return "Creating context…"
    }

    private func clearLogFlags() {
        metadataLogged = false
        backendLogged = false
        contextLogged = false
        finalizingLogged = false
    }

    private func cancelFallbacks(upTo phase: LoadingPhase? = nil) {
        if let phase {
            let threshold = phase.orderIndex
            let items = fallbackPhaseWorkItems
            for (key, work) in items where key.orderIndex <= threshold {
                work.cancel()
                fallbackPhaseWorkItems.removeValue(forKey: key)
            }
        } else {
            for (_, work) in fallbackPhaseWorkItems {
                work.cancel()
            }
            fallbackPhaseWorkItems.removeAll()
        }
    }
}

// MARK: - Progress View Component
struct ModelLoadingProgressView: View {
    @ObservedObject var tracker: ModelLoadingProgressTracker

    var body: some View {
        VStack(spacing: 6) {
            // Phase label
            Text(tracker.phaseLabel)
                .font(.caption2)
                .foregroundColor(.secondary)
                .animation(.easeInOut(duration: 0.3), value: tracker.phaseLabel)

            // Progress bar
            ZStack(alignment: .leading) {
                // Background
                Capsule()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 140, height: 4)

                // Progress fill with gradient
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue, Color.blue.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 140 * tracker.progress, height: 4)
                    .animation(.easeInOut(duration: 0.2), value: tracker.progress)

                // Shimmer effect
                if tracker.isLoading && tracker.progress < 0.95 {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0),
                                    Color.white.opacity(0.3),
                                    Color.white.opacity(0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 30, height: 4)
                        .offset(x: 140 * tracker.progress - 15)
                        .animation(
                            Animation.linear(duration: 1.5)
                                .repeatForever(autoreverses: false),
                            value: tracker.progress
                        )
                }
            }
        }
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        Color(.systemBackground)
            .ignoresSafeArea()

        VStack {
            Spacer()

            ModelLoadingNotificationView(
                modelManager: {
                    let manager = AppModelManager()
                    manager.loadingModelName = "Llama-3.2-3B-Instruct-Q4"
                    return manager
                }(),
                loadingTracker: {
                    let tracker = ModelLoadingProgressTracker()
                    tracker.isLoading = true
                    tracker.progress = 0.65
                    tracker.currentPhase = .loadingKernels
                    tracker.phaseLabel = "Loading Metal kernels..."
                    return tracker
                }()
            )

            Spacer()
        }
    }
}
