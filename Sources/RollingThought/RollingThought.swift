// RollingThought.swift
import SwiftUI

// MARK: - Token Stream Protocol
public protocol TokenStream: Sendable {
    associatedtype AsyncTokenSequence: AsyncSequence where AsyncTokenSequence.Element == String
    func tokens() -> AsyncTokenSequence
}

// MARK: - Rolling Thought View Model
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

        phase = .idle
        didReachLogicalCompletion = false
        shouldFinishWhenStreamEnds = false
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
public struct RollingThoughtBox: View {
    @ObservedObject public var viewModel: RollingThoughtViewModel
    @Namespace private var namespace
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

    public var body: some View {
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
    
    private var streamingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header similar to web search
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "brain")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Thinking")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.systemGray6))
                .clipShape(Capsule())
                
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
                                .foregroundStyle(.primary.opacity(0.8))
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
                    if shouldAutoScroll {
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
                            .foregroundStyle(.secondary.opacity(0.6))
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
        .padding(12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.gray.opacity(0.3), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.toggleExpanded()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var expandedView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "brain")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Chain of Thought")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.systemGray6))
                .clipShape(Capsule())
                
                Spacer()
                
                Button(action: { viewModel.toggleExpanded() }) {
                    Text("Collapse")
                        .font(.caption2.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.systemGray6))
                .clipShape(Capsule())
            }
            
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(viewModel.fullText.isEmpty ? "Waiting for thoughts..." : viewModel.fullText)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(.primary)
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
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                                .padding(8)
                                .background(.thinMaterial)
                                .clipShape(Circle())
                        }
                        .padding(8)
                    }
                }
                .onChange(of: viewModel.fullText) { _ in
                    if shouldAutoScroll {
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
        .padding(12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.gray.opacity(0.3), lineWidth: 0.5)
        )
    }
    
    private var completeView: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                Text("Thought complete")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.systemGray6))
            .clipShape(Capsule())
            
            Spacer()
            
            Button(action: { viewModel.toggleExpanded() }) {
                Text("View")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.systemGray6))
            .clipShape(Capsule())
        }
        .padding(8)
        .background(Color(.systemGray6).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.green.opacity(0.3), lineWidth: 0.5)
        )
    }

    private var interruptedView: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text("Thought interrupted")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.systemGray6))
            .clipShape(Capsule())

            Spacer()

            Button(action: { viewModel.toggleExpanded() }) {
                Text("View")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.systemGray6))
            .clipShape(Capsule())
        }
        .padding(8)
        .background(Color(.systemGray6).opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 0.5)
        )
    }
}
