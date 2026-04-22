// RollingThought.swift
import SwiftUI

#if os(macOS)
import AppKit
#endif

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
private extension Color {
    static var rollingThoughtSurface: Color {
#if os(macOS)
        return Color(white: 0.15)
#else
        return Color(white: 0.97)
#endif
    }

    static var rollingThoughtPillBackground: Color {
#if os(macOS)
        return Color.white.opacity(0.1)
#else
        return Color.black.opacity(0.05)
#endif
    }

    static var rollingThoughtPillForeground: Color {
#if os(macOS)
        return Color.black.opacity(0.88)
#else
        return Color.white.opacity(0.96)
#endif
    }

    static var rollingThoughtSecondaryPillBackground: Color {
#if os(macOS)
        return Color.white.opacity(0.08)
#else
        return Color.white.opacity(0.72)
#endif
    }

    static var rollingThoughtSecondaryPillForeground: Color {
#if os(macOS)
        return Color.white.opacity(0.6)
#else
        return Color.black.opacity(0.5)
#endif
    }

    static var rollingThoughtText: Color {
#if os(macOS)
        return Color.white.opacity(0.92)
#else
        return Color.black.opacity(0.86)
#endif
    }

    static var rollingThoughtSubtext: Color {
#if os(macOS)
        return Color.white.opacity(0.62)
#else
        return Color.black.opacity(0.54)
#endif
    }

    static var rollingThoughtInset: Color {
#if os(macOS)
        return Color.white.opacity(0.05)
#else
        return Color.white.opacity(0.72)
#endif
    }

    static var rollingThoughtBorder: Color {
#if os(macOS)
        return Color.white.opacity(0.1)
#else
        return Color.black.opacity(0.08)
#endif
    }

    static var rollingThoughtShadow: Color {
#if os(macOS)
        return Color.black.opacity(0.1)
#else
        return Color.black.opacity(0.04)
#endif
    }

    static var rollingThoughtWarningBackground: Color {
#if os(macOS)
        return Color(nsColor: NSColor.systemOrange.withAlphaComponent(0.10))
#else
        return Color.orange.opacity(0.08)
#endif
    }

    static var rollingThoughtWarningBorder: Color {
#if os(macOS)
        return Color(nsColor: NSColor.systemOrange).opacity(0.25)
#else
        return Color.orange.opacity(0.22)
#endif
    }
}

// MARK: - Token Stream Protocol
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public protocol TokenStream: Sendable {
    associatedtype AsyncTokenSequence: AsyncSequence where AsyncTokenSequence.Element == String
    func tokens() -> AsyncTokenSequence
}

// MARK: - Rolling Thought View Model
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
@MainActor
public final class RollingThoughtViewModel: ObservableObject {
    public enum Phase: String, Codable, Equatable {
        case idle
        case streaming
        case expanded
        case complete
        case interrupted
    }

    @Published public var phase: Phase = .idle {
        didSet {
            if phase == .complete {
                didReachLogicalCompletion = true
            } else if phase == .idle {
                didReachLogicalCompletion = false
            } else if phase == .interrupted {
                didReachLogicalCompletion = false
            }
        }
    }
    @Published public private(set) var rollingLines: [String] = []
    @Published public var fullText: String = ""
    // Tracks whether the logical stream (final </think>) has completed
    private(set) var didReachLogicalCompletion: Bool = false
    public var isLogicallyComplete: Bool { didReachLogicalCompletion }
    // If true, automatically call finish() once the currently running token stream ends
    private var shouldFinishWhenStreamEnds: Bool = false
    /// Whether the view model is waiting for its token stream to end before marking complete.
    public var isPendingCompletion: Bool { shouldFinishWhenStreamEnds }
    
    // Configuration
    public let rollingLineLimit = 3
    public let collapseLabel = "Thought."
    public let showCollapseLabelWhenComplete = true
    
    private var streamTask: Task<Void, Never>?
    private var currentLines: [String] = []
    
    // Persistence
    private let persistenceKey = "RollingThoughtViewModel.State"
    
    struct State: Codable {
        var phase: Phase
        var fullText: String
        var didReachLogicalCompletion: Bool
    }
    
    public init() {}
    
    public func start<T: TokenStream>(with stream: T) {
        // Only reset if we're starting fresh (not already streaming)
        if phase == .idle {
            reset()
        }
        // Cancel any in-flight stream without changing the current phase
        streamTask?.cancel()
        streamTask = nil
        phase = .streaming
        didReachLogicalCompletion = false
        shouldFinishWhenStreamEnds = false
        
        streamTask = Task {
            await consumeStream(stream.tokens())
        }
    }
    
    public func append<T: TokenStream>(with stream: T) {
        // For appending to existing content without resetting
        // Preserve deferred-completion intent across appends
        let preserveDeferredCompletion = shouldFinishWhenStreamEnds
        // Cancel any in-flight stream without changing the current phase
        streamTask?.cancel()
        streamTask = nil
        shouldFinishWhenStreamEnds = preserveDeferredCompletion
        if phase != .streaming && phase != .expanded {
            phase = .streaming
        }
        
        streamTask = Task {
            await consumeStream(stream.tokens())
        }
    }
    
    public func toggleExpanded() {
        switch phase {
        case .streaming:
            phase = .expanded
        case .complete:
            // Allow reopening from complete state
            phase = .expanded
        case .interrupted:
            phase = .expanded
        case .expanded:
            // Collapse back to streaming unless we have truly completed
            if didReachLogicalCompletion {
                phase = .complete
            } else if streamTask == nil {
                phase = .interrupted
            } else {
                phase = .streaming
            }
        case .idle:
            break
        }
    }

    public func finish() {
        streamTask?.cancel()
        streamTask = nil
        didReachLogicalCompletion = true
        shouldFinishWhenStreamEnds = false
        
        if phase != .expanded {
            phase = .complete
        }
        
        // Privacy option: uncomment the next line to clear full text on completion
        // fullText = ""
    }
    
    public func cancel() {
        streamTask?.cancel()
        streamTask = nil

        // Defer state mutation to the next runloop to avoid publishing
        // changes while SwiftUI is in the middle of a view update pass.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.phase = .idle
            self.didReachLogicalCompletion = false
            self.shouldFinishWhenStreamEnds = false
        }
    }

    public func markInterrupted() {
        streamTask?.cancel()
        streamTask = nil
        shouldFinishWhenStreamEnds = false
        didReachLogicalCompletion = false
        if phase != .idle {
            phase = .interrupted
        }
    }
    
    private func reset() {
        fullText = ""
        rollingLines = []
        currentLines = []
        didReachLogicalCompletion = false
        shouldFinishWhenStreamEnds = false
    }

    /// Request that the view model transition to complete immediately after the
    /// currently running token stream finishes delivering its tokens.
    public func deferCompletionUntilStreamEnds() {
        shouldFinishWhenStreamEnds = true
    }
    
    private func consumeStream<S: AsyncSequence>(_ sequence: S) async where S.Element == String {
        do {
            for try await token in sequence {
                guard !Task.isCancelled else { break }
                
                await MainActor.run {
                    fullText.append(token)
                    updateRollingLines()
                }
            }
        } catch {
            // Handle streaming errors gracefully
            print("RollingThought stream error: \(error)")
        }
        
        if !Task.isCancelled {
            await MainActor.run {
                self.streamTask = nil
                if self.shouldFinishWhenStreamEnds {
                    self.finish()
                }
            }
        }
    }
    
    public func updateRollingLines() {
        // Split text into lines
        let allLines = fullText.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        
        // Get the last N lines for rolling display
        var visibleLines = Array(allLines.suffix(rollingLineLimit))
        
        // Ensure we always have consistent line count to prevent height changes
        while visibleLines.count < rollingLineLimit {
            visibleLines.insert("", at: 0)
        }
        
        // Update with a subtle animation to reveal the rolling effect
        withAnimation(.linear(duration: 0.12)) {
            rollingLines = visibleLines
        }
    }
    
    // MARK: - Persistence
    public func saveState() {
        let state = State(phase: phase, fullText: fullText, didReachLogicalCompletion: didReachLogicalCompletion)
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: persistenceKey)
        }
    }
    
    public func loadState() {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey),
              let state = try? JSONDecoder().decode(State.self, from: data) else {
            return
        }
        self.phase = state.phase
        self.fullText = state.fullText
        self.didReachLogicalCompletion = state.didReachLogicalCompletion
        updateRollingLines()
    }
    
    public func saveState(forKey key: String) {
        let state = State(phase: phase, fullText: fullText, didReachLogicalCompletion: didReachLogicalCompletion)
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    
    public func loadState(forKey key: String) {
        guard let data = UserDefaults.standard.data(forKey: key),
              let state = try? JSONDecoder().decode(State.self, from: data) else {
            return
        }
        self.phase = state.phase
        self.fullText = state.fullText
        self.didReachLogicalCompletion = state.didReachLogicalCompletion
        updateRollingLines()
    }
}

// MARK: - Rolling Thought Box Component
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public struct RollingThoughtBox: View {
    @ObservedObject public var viewModel: RollingThoughtViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var namespace
    @State private var isAppearing = false
    @State private var shouldAutoScroll: Bool = true

    public init(viewModel: RollingThoughtViewModel) {
        self.viewModel = viewModel
    }

    private var streamingLineCount: Int {
        let rawLines = viewModel.fullText.components(separatedBy: "\n")
        let lineCount = max(rawLines.count, viewModel.fullText.isEmpty ? 1 : 0)
        return min(max(lineCount, 1), viewModel.rollingLineLimit)
    }

    private var streamingContentHeight: CGFloat {
        CGFloat(streamingLineCount) * 14.0
    }

    private var thoughtSurfaceBackground: Color {
        .rollingThoughtSurface
    }

    private var thoughtSurfaceBorder: Color {
        .rollingThoughtBorder
    }

    private var thoughtPillBackground: Color {
        .rollingThoughtPillBackground
    }

    private var thoughtPillForeground: Color {
        .rollingThoughtPillForeground
    }

    private var thoughtSecondaryPillBackground: Color {
        .rollingThoughtSecondaryPillBackground
    }

    private var thoughtSecondaryPillForeground: Color {
        .rollingThoughtSecondaryPillForeground
    }

    private var thoughtTextColor: Color {
        .rollingThoughtText
    }

    private var thoughtSubtextColor: Color {
        .rollingThoughtSubtext
    }

    private var thoughtInsetBackground: Color {
        .rollingThoughtInset
    }

    private var cardCornerRadius: CGFloat {
        18
    }

    private var insetCornerRadius: CGFloat {
        14
    }

    public var body: some View {
        ZStack {
            ZStack {
                switch viewModel.phase {
                case .idle:
                    EmptyView()
                    
                case .streaming:
                    streamingView
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.9, anchor: .leading).combined(with: .opacity),
                            removal: .identity
                        ))
                    
                case .expanded:
                    expandedView
                        .transition(.identity)

                case .complete:
                    if viewModel.showCollapseLabelWhenComplete {
                        completeView
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.9, anchor: .center).combined(with: .opacity),
                                removal: .identity
                            ))
                    } else {
                        // Keep a minimal placeholder to prevent layout jump when box completes
                        Color.clear.frame(height: 1)
                    }

                case .interrupted:
                    interruptedView
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.9, anchor: .center).combined(with: .opacity),
                            removal: .identity
                        ))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.phase)
            .id(viewModel.phase) // Force view identity update on phase change
        }
        .opacity(isAppearing ? 1 : 0)
        .scaleEffect(isAppearing ? 1 : 0.98)
        .onAppear {
            guard !isAppearing else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isAppearing = true
            }
        }
    }
    
    private var streamingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(thoughtSubtextColor)
                    Text("THINKING")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(0.5)
                        .foregroundColor(thoughtSubtextColor)
                }
                
                Spacer()
            }
            
            // Rolling content with auto-scroll to the currently generating line
            ScrollViewReader { proxy in
                ScrollView { 
                    VStack(alignment: .leading, spacing: 0) {
                        let allLines = viewModel.fullText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                        ForEach(Array(allLines.enumerated()), id: \.offset) { i, l in
                            Text(l.isEmpty ? " " : l)
                                .id("rt-line-\(i)")
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundColor(thoughtTextColor.opacity(0.82))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(minHeight: 14)
                        }
                        // Bottom anchor to ensure reliable auto-scroll as content grows
                        Color.clear
                            .frame(height: 1)
                            .id("rt-bottom")
                    }
                }
                .frame(height: streamingContentHeight)
                .padding(.horizontal, 4)
                .simultaneousGesture(DragGesture().onChanged { _ in shouldAutoScroll = false })
                .onChange(of: viewModel.fullText) { _ in
                    guard shouldAutoScroll else { return }
                    DispatchQueue.main.async {
                        guard shouldAutoScroll else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo("rt-bottom", anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    // Scroll to bottom on first appear so the generating line is visible
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo("rt-bottom", anchor: .bottom)
                        }
                        shouldAutoScroll = true
                    }
                }
                .overlay(alignment: .topLeading) {
                    if viewModel.phase == .streaming && viewModel.fullText.isEmpty {
                        Text("• • •")
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundColor(thoughtSubtextColor)
                    }
                }
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.8),
                            .init(color: .black.opacity(0.2), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .padding(14)
        .background(thoughtSurfaceBackground)
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .strokeBorder(thoughtSurfaceBorder, lineWidth: 0.6)
        )
        .shadow(color: .rollingThoughtShadow, radius: 8, x: 0, y: 4)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.toggleExpanded()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var expandedView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(thoughtSubtextColor)
                    Text("CHAIN OF THOUGHT")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(0.5)
                        .foregroundColor(thoughtSubtextColor)
                }
                
                Spacer()
                Button(action: { viewModel.toggleExpanded() }) {
                    Text("Collapse")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                }
                .buttonStyle(.plain)
                .foregroundColor(thoughtSecondaryPillForeground)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(viewModel.fullText.isEmpty ? "Waiting for thoughts..." : viewModel.fullText)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundColor(thoughtTextColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(8)
                            .id("fullText")
                        // Bottom anchor to ensure reliable auto-scroll as content grows
                        Color.clear
                            .frame(height: 1)
                            .id("scrollBottom")
                    }
                }
                .frame(maxHeight: 200)
                .background(thoughtInsetBackground)
                .clipShape(RoundedRectangle(cornerRadius: insetCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: insetCornerRadius, style: .continuous)
                        .stroke(thoughtSurfaceBorder, lineWidth: 0.6)
                )
                .simultaneousGesture(DragGesture().onChanged { _ in shouldAutoScroll = false })
                .overlay(alignment: .bottomTrailing) {
                    if !shouldAutoScroll && viewModel.phase == .streaming {
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo("scrollBottom", anchor: .bottom)
                            }
                            shouldAutoScroll = true
                        } label: {
                            Image(systemName: "arrow.down")
                                .font(.caption)
                                .padding(6)
                                .foregroundColor(thoughtSubtextColor)
                                .background(thoughtSecondaryPillBackground)
                                .clipShape(Circle())
                        }
                        .padding(8)
                    }
                }
                .onChange(of: viewModel.fullText) { _ in
                    guard shouldAutoScroll else { return }
                    DispatchQueue.main.async {
                        guard shouldAutoScroll else { return }
                        proxy.scrollTo("scrollBottom", anchor: .bottom)
                    }
                }
                .onAppear {
                    // Scroll to bottom on first appear as well
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo("scrollBottom", anchor: .bottom)
                        }
                        shouldAutoScroll = true
                    }
                }
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [
                    thoughtSurfaceBackground,
                    thoughtSurfaceBackground.opacity(colorScheme == .dark ? 0.92 : 0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .strokeBorder(thoughtSurfaceBorder, lineWidth: 0.6)
        )
        .shadow(color: .rollingThoughtShadow, radius: 16, x: 0, y: 10)
    }
    
    private var completeView: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(thoughtSubtextColor)
                Text("THOUGHT COMPLETE")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(0.5)
                    .foregroundColor(thoughtSubtextColor)
            }
            
            Spacer()
            
            Button(action: { viewModel.toggleExpanded() }) {
                Text("View")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(thoughtSecondaryPillForeground)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .padding(10)
        .background(thoughtSurfaceBackground)
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .strokeBorder(thoughtSurfaceBorder, lineWidth: 0.6)
        )
        .shadow(color: .rollingThoughtShadow, radius: 4, x: 0, y: 2)
    }

    private var interruptedView: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.orange)
                Text("THOUGHT INTERRUPTED")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(0.8)
                    .foregroundColor(.orange)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(thoughtSecondaryPillBackground)
            .clipShape(Capsule())

            Spacer()

            Button(action: { viewModel.toggleExpanded() }) {
                Text("View")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(thoughtSecondaryPillForeground)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .padding(10)
        .background(Color.rollingThoughtWarningBackground)
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .strokeBorder(Color.rollingThoughtWarningBorder, lineWidth: 0.6)
        )
        .shadow(color: .rollingThoughtShadow, radius: 4, x: 0, y: 2)
    }
}
