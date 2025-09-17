// ModelLoadingProgressTracker.swift
import Foundation
import SwiftUI

/// Tracks model loading progress with realistic phases
@MainActor
final class ModelLoadingProgressTracker: ObservableObject {
    enum LoadingPhase {
        case initializing
        case loadingFile
        case loadingKernels
        case creatingContext
        case finalizing
        case complete
        
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
    }
    
    @Published var currentPhase: LoadingPhase = .initializing
    @Published var progress: Double = 0.0
    @Published var phaseLabel: String = ""
    @Published var isLoading: Bool = false
    
    private var timer: Timer?
    private var targetProgress: Double = 0.0
    // Expose format for UI (read-only)
    private(set) var loadingFormat: ModelFormat = .gguf
    
    func startLoading(for format: ModelFormat) {
        isLoading = true
        loadingFormat = format
        currentPhase = .initializing
        progress = 0.0
        phaseLabel = currentPhase.label
        targetProgress = currentPhase.targetProgress
        
        // Start animation timer
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateProgress()
            }
        }
        
        // Schedule phase transitions
        schedulePhaseTransitions()
    }
    
    func completeLoading() {
        currentPhase = .complete
        targetProgress = 1.0
        
        // Quick animation to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.timer?.invalidate()
            self?.timer = nil
            self?.progress = 1.0
            self?.isLoading = false
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
                guard self?.isLoading == true else { return }
                self?.transitionToPhase(phase)
            }
        }
    }
    
    private func transitionToPhase(_ phase: LoadingPhase) {
        guard isLoading else { return }
        currentPhase = phase
        phaseLabel = phase.label
        targetProgress = phase.targetProgress
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
            .shadow(color: Color.blue.opacity(0.3), radius: 2, x: 0, y: 1)
        }
    }
}
