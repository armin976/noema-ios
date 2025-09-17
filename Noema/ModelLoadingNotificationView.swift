// ModelLoadingNotificationView.swift
import SwiftUI
import UIKit

struct ModelLoadingNotificationView: View {
    @ObservedObject var modelManager: AppModelManager
    @ObservedObject var loadingTracker: ModelLoadingProgressTracker
    @State private var showNotification = false
    @State private var animateIn = false
    @State private var animateOut = false
    // Persist whether user has ever loaded a GGUF model before
    @AppStorage("hasLoadedGGUFOnce") private var hasLoadedGGUFOnce: Bool = false
    
    private let phases = ModelLoadingProgressTracker.LoadingPhase.allCases
    
    // Compact pill width – expands on first-time GGUF load so tip fits fully
    private var pillWidth: CGFloat {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let isFirstGGUFLoad = (loadingTracker.loadingFormat == .gguf && !hasLoadedGGUFOnce)
        if isFirstGGUFLoad {
            // Widen to show the full tip text without truncation
            return isPad ? 340 : 260
        } else {
            // Default compact size (kept smaller than the dynamic island)
            return isPad ? 220 : 120
        }
    }
    
    var body: some View {
        ZStack {
            if showNotification {
                content
                    .scaleEffect(animateIn ? 1.0 : 0.9)
                    .opacity(animateIn ? 1.0 : 0.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: animateIn)
                    .animation(.easeOut(duration: 0.25), value: animateOut)
            }
        }
        .onAppear {
            // If the view appears while a load is already in progress, show immediately
            if loadingTracker.isLoading {
                showNotification = true
                animateIn = false
                animateOut = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    animateIn = true
                }
            }
        }
        .onChange(of: loadingTracker.isLoading) { wasLoading, isLoading in
            if isLoading && !wasLoading {
                // Just started loading
                showNotification = true
                animateIn = false
                animateOut = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    animateIn = true
                }
            } else if !isLoading && wasLoading {
                // Just finished loading (whether success or failure)
                withAnimation(.easeOut(duration: 0.25)) {
                    animateOut = true
                    animateIn = false
                }
                // Mark that we've gone through a GGUF load at least once
                if loadingTracker.loadingFormat == .gguf {
                    hasLoadedGGUFOnce = true
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    showNotification = false
                    animateOut = false
                }
            }
        }
    }
    
    @ViewBuilder
    private var content: some View {
        VStack(spacing: 8) {
            // Phase indicator dots - 5 circles at the top
            HStack(spacing: 8) {
                ForEach(phases.indices, id: \.self) { index in
                    Circle()
                        .fill(phaseColor(phases[index]))
                        .frame(width: 8, height: 8)
                        .scaleEffect(phases[index] == loadingTracker.currentPhase ? 1.3 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: loadingTracker.currentPhase)
                }
            }
            
            // Phase label text
            Text(loadingTracker.phaseLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .animation(.easeInOut(duration: 0.3), value: loadingTracker.phaseLabel)
                .lineLimit(1)
                .truncationMode(.tail)

            // One-time tip: first GGUF load can take longer
            if loadingTracker.loadingFormat == .gguf && !hasLoadedGGUFOnce {
                Text("First-time GGUF load takes longer")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(width: pillWidth)
        .background(
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.thinMaterial)
                    // Progress fill as the pill itself (left-to-right)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.35), Color.blue.opacity(0.25)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, min(1, loadingTracker.progress)) * geo.size.width)
                        .animation(.easeInOut(duration: 0.25), value: loadingTracker.progress)
                }
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
            }
        )
        .padding(.horizontal, UIDevice.current.userInterfaceIdiom == .pad ? 40 : 20)
        .opacity(animateOut ? 0.0 : 1.0)
        .scaleEffect(animateOut ? 0.9 : (animateIn ? 1.0 : 0.95))
    }
    
    private func phaseColor(_ phase: ModelLoadingProgressTracker.LoadingPhase) -> Color {
        let currentIndex = phases.firstIndex(of: loadingTracker.currentPhase) ?? 0
        let phaseIndex = phases.firstIndex(of: phase) ?? 0
        
        if phaseIndex < currentIndex {
            return .green // Completed phases
        } else if phaseIndex == currentIndex {
            return .blue // Current phase
        } else {
            return .gray.opacity(0.3) // Future phases
        }
    }
}

// Extension to make LoadingPhase CaseIterable for easy iteration
extension ModelLoadingProgressTracker.LoadingPhase: CaseIterable {
    static var allCases: [ModelLoadingProgressTracker.LoadingPhase] {
        [.initializing, .loadingFile, .loadingKernels, .creatingContext, .finalizing]
    }
}

// Preview
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
