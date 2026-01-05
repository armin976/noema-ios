// ModelLoadingNotificationView.swift

import SwiftUI

// Cross-version helper for SwiftUI's onChange(old,new) added in iOS 17/macOS 14.
// For earlier OS versions, it falls back to the older onChange(new) and
// synthesizes the previous value.
private struct OnChangeCompatibilityModifier<Value: Equatable>: ViewModifier {
    let value: Value
    let initial: Bool
    let action: (Value, Value) -> Void
    @State private var previous: Value?

    func body(content: Content) -> some View {
        content
            .onAppear {
                if previous == nil {
                    previous = value
                    if initial {
                        action(value, value)
                    }
                }
            }
            .onChange(of: value) { newValue in
                let old = previous ?? newValue
                previous = newValue
                action(old, newValue)
            }
    }
}

extension View {
    @ViewBuilder
    func onChangeCompat<Value: Equatable>(of value: Value, initial: Bool = false, _ action: @escaping (_ old: Value, _ new: Value) -> Void) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            self.onChange(of: value, initial: initial, action)
        } else {
            self.modifier(OnChangeCompatibilityModifier(value: value, initial: initial, action: action))
        }
    }
}

@MainActor
protocol ModelLoadingManaging: ObservableObject {
    var loadingModelName: String? { get set }
}

#if DEBUG
@MainActor
final class PreviewModelManager: ObservableObject, ModelLoadingManaging {
    @Published var loadingModelName: String?
}
#endif

#if canImport(UIKit)
import SwiftUI
import UIKit

struct ModelLoadingNotificationView<Manager: ModelLoadingManaging>: View {
    @ObservedObject var modelManager: Manager
    @ObservedObject var loadingTracker: ModelLoadingProgressTracker
    @State private var showNotification = false
    @State private var animateIn = false
    @State private var animateOut = false
    @Environment(\.colorScheme) private var colorScheme
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
                animateOut = false
                animateIn = false
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        animateIn = true
                    }
                }
            }
        }
        .onChangeCompat(of: loadingTracker.isLoading) { wasLoading, isLoading in
            if isLoading && !wasLoading {
                // Just started loading
                showNotification = true
                animateOut = false
                animateIn = false
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        animateIn = true
                    }
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
                .foregroundStyle(.primary)
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
        .background(backgroundCapsule)
        .padding(.horizontal, UIDevice.current.userInterfaceIdiom == .pad ? 40 : 20)
        .opacity(animateOut ? 0.0 : 1.0)
        .scaleEffect(animateOut ? 0.9 : (animateIn ? 1.0 : 0.95))
    }

    private func phaseColor(_ phase: ModelLoadingProgressTracker.LoadingPhase) -> Color {
        let currentIndex = phases.firstIndex(of: loadingTracker.currentPhase) ?? 0
        let phaseIndex = phases.firstIndex(of: phase) ?? 0
        let accent = Color.accentColor
        if phaseIndex < currentIndex {
            return accent.opacity(0.35)
        } else if phaseIndex == currentIndex {
            return accent
        } else {
            return accent.opacity(0.18)
        }
    }

    private var backgroundCapsule: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(baseBackgroundColor)
                Capsule()
                    .fill(progressFillColor)
                    .frame(width: max(0, min(1, loadingTracker.progress)) * geo.size.width)
                    .animation(.easeInOut(duration: 0.25), value: loadingTracker.progress)
            }
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(borderColor, lineWidth: 0.6)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.38 : 0.08), radius: 6, x: 0, y: 3)
        }
    }

    private var baseBackgroundColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.55)
            : Color.white.opacity(0.92)
    }

    private var progressFillColor: Color {
        Color.accentColor.opacity(colorScheme == .dark ? 0.35 : 0.22)
    }

    private var borderColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.28 : 0.08)
    }
}

#if DEBUG
// Preview
#Preview {
    ZStack {
        Color(.systemBackground)
            .ignoresSafeArea()

        VStack {
            Spacer()

            ModelLoadingNotificationView(
                modelManager: {
                    let manager = PreviewModelManager()
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
#endif
#elseif os(macOS)
import SwiftUI
import AppKit

struct ModelLoadingNotificationView<Manager: ModelLoadingManaging>: View {
    @ObservedObject var modelManager: Manager
    @ObservedObject var loadingTracker: ModelLoadingProgressTracker
    @State private var showNotification = false
    @State private var animateIn = false
    @State private var animateOut = false
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("hasLoadedGGUFOnce") private var hasLoadedGGUFOnce: Bool = false

    private let phases = ModelLoadingProgressTracker.LoadingPhase.allCases
    private let pillWidth: CGFloat = 260

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
            if loadingTracker.isLoading {
                showNotification = true
                animateOut = false
                animateIn = false
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        animateIn = true
                    }
                }
            }
        }
        .onChangeCompat(of: loadingTracker.isLoading) { wasLoading, isLoading in
            if isLoading && !wasLoading {
                showNotification = true
                animateOut = false
                animateIn = false
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        animateIn = true
                    }
                }
            } else if !isLoading && wasLoading {
                withAnimation(.easeOut(duration: 0.25)) {
                    animateOut = true
                    animateIn = false
                }
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
            HStack(spacing: 8) {
                ForEach(phases.indices, id: \.self) { index in
                    Circle()
                        .fill(phaseColor(phases[index]))
                        .frame(width: 8, height: 8)
                        .scaleEffect(phases[index] == loadingTracker.currentPhase ? 1.3 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: loadingTracker.currentPhase)
                }
            }

            Text(loadingTracker.phaseLabel)
                .font(.caption2)
                .foregroundStyle(primaryTextColor)
                .animation(.easeInOut(duration: 0.3), value: loadingTracker.phaseLabel)
                .lineLimit(1)
                .truncationMode(.tail)

            if loadingTracker.loadingFormat == .gguf && !hasLoadedGGUFOnce {
                Text("First-time GGUF load takes longer")
                    .font(.caption2)
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(width: pillWidth)
        .background(backgroundCapsule)
        .padding(.horizontal, 32)
        .opacity(animateOut ? 0.0 : 1.0)
        .scaleEffect(animateOut ? 0.9 : (animateIn ? 1.0 : 0.95))
    }

    private func phaseColor(_ phase: ModelLoadingProgressTracker.LoadingPhase) -> Color {
        let currentIndex = phases.firstIndex(of: loadingTracker.currentPhase) ?? 0
        let phaseIndex = phases.firstIndex(of: phase) ?? 0
        let accent = Color(nsColor: .controlAccentColor)
        if phaseIndex < currentIndex {
            return accent.opacity(0.35)
        } else if phaseIndex == currentIndex {
            return accent
        } else {
            return accent.opacity(0.18)
        }
    }

    private var backgroundCapsule: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(baseBackgroundColor)
                Capsule()
                    .fill(progressFillColor)
                    .frame(width: max(0, min(1, loadingTracker.progress)) * geo.size.width)
                    .animation(.easeInOut(duration: 0.25), value: loadingTracker.progress)
            }
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(borderColor, lineWidth: 0.6)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.38 : 0.1), radius: 6, x: 0, y: 3)
        }
    }

    private var baseBackgroundColor: Color {
        let base = Color(nsColor: .textBackgroundColor)
        return colorScheme == .dark
            ? base.opacity(0.7)
            : base.opacity(0.94)
    }

    private var progressFillColor: Color {
        Color(nsColor: .controlAccentColor).opacity(colorScheme == .dark ? 0.55 : 0.28)
    }

    private var borderColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.28 : 0.08)
    }

    private var primaryTextColor: Color {
        Color(nsColor: .labelColor)
    }

    private var secondaryTextColor: Color {
        Color(nsColor: .secondaryLabelColor)
    }
}

#if DEBUG
#Preview {
    ZStack {
        Color.black.opacity(0.5).ignoresSafeArea()
        ModelLoadingNotificationView(
            modelManager: PreviewModelManager(),
            loadingTracker: ModelLoadingProgressTracker.preview
        )
    }
}
#endif
#endif
