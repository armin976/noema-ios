import SwiftUI

struct ToolCallView: View {
    let toolCall: ChatVM.Msg.ToolCall

    @Environment(\.colorScheme) private var colorScheme
    @State private var showingDetails = false
    @State private var isAppearing = false
    @State private var loadingSweepOffset: CGFloat = 0
    @State private var loadingSweepCardWidth: CGFloat = 0
    @State private var showCompletionSweep = false
    @State private var completionSweepProgress: CGFloat = 0.02
    @State private var completionSweepOpacity = 0.0
    @State private var completionSweepTask: Task<Void, Never>?

    private var surfaceColor: Color {
        toolCall.phase == .failed
            ? Color.orange.opacity(0.10)
            : (colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.97))
    }

    private var surfaceBorderColor: Color {
        toolCall.phase == .failed
            ? Color.orange.opacity(0.24)
            : Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.10)
    }

    private var secondaryPillForegroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.5)
    }

    private var cardShadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.1) : Color.black.opacity(0.04)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
    }

    private var loadingSweepShoulderOpacity: Double {
        colorScheme == .dark ? 0.22 : 0.16
    }

    private var loadingSweepCoreOpacity: Double {
        colorScheme == .dark ? 0.26 : 0.5
    }

    private var completionSweepColor: Color {
        Color(red: 0.24, green: 0.82, blue: 0.47)
    }

    private var parameterSummaryEntries: [ToolCallViewSupport.ParameterSummaryEntry] {
        ToolCallViewSupport.parameterSummaryEntries(from: toolCall.requestParams)
    }

    private var remainingParameterCount: Int {
        ToolCallViewSupport.remainingParameterCount(from: toolCall.requestParams)
    }

    private var isWebSearchActive: Bool {
        ToolCallViewSupport.isActiveWebSearch(toolName: toolCall.toolName, phase: toolCall.phase)
    }

    var body: some View {
        Button(action: { showingDetails = true }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: toolCall.iconName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(secondaryPillForegroundColor)
                        Text(toolCall.displayName.uppercased())
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .tracking(0.5)
                            .foregroundStyle(secondaryPillForegroundColor)
                    }

                    Spacer()

                    statusIndicator
                }

                Text(toolCall.toolName)
                    .font(.caption2)
                    .foregroundStyle(secondaryPillForegroundColor)

                if !parameterSummaryEntries.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(parameterSummaryEntries) { entry in
                            HStack(spacing: 4) {
                                Text("\(entry.key):")
                                    .font(.caption2)
                                    .foregroundStyle(secondaryPillForegroundColor)
                                Text(entry.value)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.82))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                        if remainingParameterCount > 0 {
                            Text("... and \(remainingParameterCount) more")
                                .font(.caption2)
                                .foregroundStyle(secondaryPillForegroundColor)
                                .italic()
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
            .padding(14)
            .background(surfaceColor)
            .clipShape(cardShape)
            .overlay(
                cardShape
                    .strokeBorder(surfaceBorderColor, lineWidth: 0.6)
            )
            .shadow(color: cardShadowColor, radius: 8, x: 0, y: 4)
            .overlay(
                GeometryReader { geo in
                    #if !os(visionOS)
                    if isWebSearchActive {
                        loadingSweepOverlay(in: geo.size)
                            .onAppear {
                                startLoadingSweep(cardWidth: geo.size.width)
                            }
                            .onChangeCompat(of: geo.size.width) { _, newWidth in
                                startLoadingSweep(cardWidth: newWidth)
                            }
                    }
                    #endif
                }
                .clipShape(cardShape)
                .allowsHitTesting(false)
            )
            .overlay(
                Group {
                    if showCompletionSweep {
                        completionSweepOverlay
                    }
                }
                .allowsHitTesting(false)
            )
        }
        .buttonStyle(.plain)
        .opacity(isAppearing ? 1 : 0)
        .scaleEffect(isAppearing ? 1 : 0.98)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isAppearing = true
            }
            initializeAnimationState()
        }
        .onDisappear {
            stopLoadingSweep()
            completionSweepTask?.cancel()
        }
        .onChangeCompat(of: toolCall.phase) { oldPhase, newPhase in
            guard oldPhase != newPhase else { return }
            handlePhaseChange(newPhase)
        }
        .toolCallDetailPresentation(isPresented: $showingDetails, toolCall: toolCall)
    }

    @ViewBuilder
    private func loadingSweepOverlay(in size: CGSize) -> some View {
        let width = max(size.width * 0.6, 1)
        let height = max(size.height * 1.8, 1)

        LinearGradient(
            colors: [
                .clear,
                Color.accentColor.opacity(loadingSweepShoulderOpacity),
                Color.white.opacity(loadingSweepCoreOpacity),
                Color.accentColor.opacity(loadingSweepShoulderOpacity),
                .clear
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: width, height: height)
        .blur(radius: 4)
        .rotationEffect(.degrees(12))
        .offset(x: loadingSweepOffset)
        .blendMode(.screen)
    }

    private var completionSweepOverlay: some View {
        let segmentStart = max(0.001, completionSweepProgress - 0.18)
        let segmentEnd = max(segmentStart + 0.001, completionSweepProgress)
        let trimmedShape = cardShape.trim(from: segmentStart, to: segmentEnd)

        return ZStack {
            trimmedShape
                .stroke(
                    completionSweepColor.opacity(completionSweepOpacity * 0.35),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: 3)

            trimmedShape
                .stroke(
                    completionSweepColor.opacity(completionSweepOpacity),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )
        }
        .rotationEffect(.degrees(-90))
    }

    private func initializeAnimationState() {
        if !toolCall.phase.isInFlight {
            stopLoadingSweep()
        }

        if ToolCallViewSupport.shouldAnimateCompletionSweep(toolName: toolCall.toolName, phase: toolCall.phase) {
            playCompletionSweep()
        } else if toolCall.phase == .completed || toolCall.phase == .failed {
            resetCompletionSweep()
        }
    }

    private func handlePhaseChange(_ phase: ChatVM.Msg.ToolCallPhase) {
        if !phase.isInFlight {
            stopLoadingSweep()
        }

        if ToolCallViewSupport.shouldAnimateCompletionSweep(toolName: toolCall.toolName, phase: phase) {
            playCompletionSweep()
            return
        }

        resetCompletionSweep()
        if loadingSweepCardWidth > 0,
           ToolCallViewSupport.isActiveWebSearch(toolName: toolCall.toolName, phase: phase) {
            startLoadingSweep(cardWidth: loadingSweepCardWidth)
        }
    }

    private func startLoadingSweep(cardWidth: CGFloat) {
        guard cardWidth > 0 else { return }
        loadingSweepCardWidth = cardWidth

        let startOffset = -cardWidth * 0.9
        let endOffset = cardWidth * 0.9

        var resetTransaction = Transaction()
        resetTransaction.disablesAnimations = true
        withTransaction(resetTransaction) {
            loadingSweepOffset = startOffset
        }

        withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
            loadingSweepOffset = endOffset
        }
    }

    private func stopLoadingSweep() {
        var resetTransaction = Transaction()
        resetTransaction.disablesAnimations = true
        withTransaction(resetTransaction) {
            loadingSweepOffset = 0
        }
    }

    private func playCompletionSweep() {
        completionSweepTask?.cancel()

        var resetTransaction = Transaction()
        resetTransaction.disablesAnimations = true
        withTransaction(resetTransaction) {
            showCompletionSweep = true
            completionSweepProgress = 0.02
            completionSweepOpacity = 1
        }

        withAnimation(.linear(duration: 0.85)) {
            completionSweepProgress = 1
        }

        completionSweepTask = Task {
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) {
                    completionSweepOpacity = 0
                }
            }

            try? await Task.sleep(nanoseconds: 260_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                resetCompletionSweep()
            }
        }
    }

    private func resetCompletionSweep() {
        completionSweepTask?.cancel()
        completionSweepTask = nil

        var resetTransaction = Transaction()
        resetTransaction.disablesAnimations = true
        withTransaction(resetTransaction) {
            showCompletionSweep = false
            completionSweepProgress = 0.02
            completionSweepOpacity = 0
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if toolCall.phase == .failed {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption.bold())
                .foregroundStyle(.orange)
        } else if toolCall.phase == .completed {
            Image(systemName: "checkmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(secondaryPillForegroundColor)
        } else {
            ProgressView()
                .scaleEffect(0.7)
        }
    }
}

struct ToolCallDetailSheet: View {
    let toolCall: ChatVM.Msg.ToolCall

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var resultDisplayMode: ToolCallViewSupport.ResultDisplayMode

    init(toolCall: ChatVM.Msg.ToolCall) {
        self.toolCall = toolCall
        _resultDisplayMode = State(
            initialValue: ToolCallViewSupport.defaultResultDisplayMode(
                toolName: toolCall.toolName,
                result: toolCall.result
            )
        )
    }

    private var sectionBackgroundColor: Color {
        colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.97)
    }

    private var sectionBorderColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.10)
    }

    private var neutralPillBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)
    }

    private var neutralPillForegroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.8) : Color.black.opacity(0.7)
    }

    private var secondaryPillForegroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.5)
    }

    private var monospaceBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.02)
    }

    private var warningBackgroundColor: Color {
        Color.orange.opacity(0.08)
    }

    private var warningBorderColor: Color {
        Color.orange.opacity(0.18)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerSection
                    requestParameterSection

                    if let error = toolCall.error {
                        errorSection(error)
                        if let result = toolCall.result {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Raw Response")
                                    .font(.headline)
                                rawResultView(for: result)
                            }
                        }
                    } else if let result = toolCall.result {
                        resultSection(result)
                    } else {
                        inFlightSection
                    }

                    Spacer(minLength: 20)
                }
                .padding()
            }
            .navigationTitle("Tool Call Details")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(macOS)
                ToolbarItem(placement: .automatic) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
                #else
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
                #endif
            }
            .onChangeCompat(of: toolCall.result) { _, newValue in
                guard let newValue else { return }
                if resultDisplayMode == .formatted,
                   !ToolCallViewSupport.supportsFormattedResultDisplay(
                    toolName: toolCall.toolName,
                    result: newValue
                   ) {
                    resultDisplayMode = .raw
                }
            }
        }
    }

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: toolCall.iconName)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(toolCall.phase == .failed ? .orange : secondaryPillForegroundColor)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(toolCall.displayName)
                    .font(.headline)
                Text(toolCall.toolName)
                    .font(.caption)
                    .foregroundColor(secondaryPillForegroundColor)
                Text(toolCall.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(secondaryPillForegroundColor)
            }

            Spacer()
        }
        .padding()
        .background(sectionBackgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(sectionBorderColor, lineWidth: 0.8)
        )
        .cornerRadius(12)
    }

    private var requestParameterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Request Parameters")
                .font(.headline)

            if toolCall.requestParams.isEmpty {
                Text("No parameters")
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(toolCall.requestParams.keys.sorted()), id: \.self) { key in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(key)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(secondaryPillForegroundColor)

                            Text(ToolCallViewSupport.formatParameterValue(toolCall.requestParams[key]?.value))
                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(monospaceBackgroundColor)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(sectionBorderColor, lineWidth: 0.8)
                                )
                                .cornerRadius(6)
                        }
                    }
                }
            }
        }
        .padding()
        .background(sectionBackgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(sectionBorderColor, lineWidth: 0.8)
        )
        .cornerRadius(8)
    }

    private func errorSection(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Error")
                    .font(.headline)
                    .foregroundColor(.orange)
            }

            Text(error)
                .font(.caption)
                .textSelection(.enabled)
                .padding()
                .background(warningBackgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(warningBorderColor, lineWidth: 0.8)
                )
                .cornerRadius(8)
        }
    }

    private func resultSection(_ result: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.secondary)
                    Text("Result")
                        .font(.headline)
                        .foregroundColor(.primary)
                }

                Spacer()

                Picker("Result format", selection: $resultDisplayMode) {
                    ForEach(ToolCallViewSupport.ResultDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 180)
            }

            Group {
                if resultDisplayMode == .formatted {
                    formattedResultView(for: result)
                } else {
                    rawResultView(for: result)
                }
            }
            .animation(.none, value: resultDisplayMode)
        }
    }

    private var inFlightSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: toolCall.phase == .requesting ? "clock.fill" : "play.circle.fill")
                    .foregroundColor(secondaryPillForegroundColor)
                Text(toolCall.phase == .requesting ? "Requesting Tool" : "Running Tool")
                    .font(.headline)
                    .foregroundColor(.primary)
            }

            Text(toolCall.phase == .requesting ? "The model is still composing the tool request." : "Waiting for tool response…")
                .font(.caption)
                .foregroundColor(.secondary)
                .italic()
        }
    }

    @ViewBuilder
    private func formattedResultView(for result: String) -> some View {
        switch ToolCallViewSupport.toolKind(for: toolCall.toolName) {
        case .python:
            pythonResultView(for: result)
        case .memory:
            memoryResultView(for: result)
        case .webSearch:
            let hits = ToolCallViewSupport.parseWebResults(from: result)
            if hits.isEmpty {
                unavailableFormattedResultView
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(hits.enumerated()), id: \.offset) { index, item in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("\(index + 1).")
                                        .font(.headline.weight(.semibold))
                                    Text(item.displayTitle.isEmpty ? "Untitled Result" : item.displayTitle)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                        .multilineTextAlignment(.leading)
                                }

                                if !item.snippet.isEmpty {
                                    Text(item.snippet.strippingHTMLTags())
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                if !item.url.isEmpty {
                                    if let destination = URL(string: item.url) ?? URL(string: "https://" + item.url) {
                                        Link(item.url, destination: destination)
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                            .lineLimit(2)
                                    } else {
                                        Text(item.url)
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                            .lineLimit(2)
                                            .textSelection(.enabled)
                                    }
                                }

                                if item.engine != nil {
                                    HStack(spacing: 6) {
                                        if let engine = item.engine, !engine.isEmpty {
                                            Text(engine)
                                                .font(.caption2.weight(.semibold))
                                                .foregroundColor(neutralPillForegroundColor)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(neutralPillBackgroundColor)
                                                .clipShape(Capsule())
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(sectionBackgroundColor)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(sectionBorderColor, lineWidth: 0.8)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
                .modifier(
                    ResultBoxStyle(
                        backgroundColor: sectionBackgroundColor,
                        borderColor: sectionBorderColor
                    )
                )
            }
        case .generic:
            unavailableFormattedResultView
        }
    }

    @ViewBuilder
    private func memoryResultView(for result: String) -> some View {
        if let response = ToolCallViewSupport.parseMemoryResult(from: result) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(response.operation.uppercased())
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(neutralPillBackgroundColor)
                        .clipShape(Capsule())
                    if let message = response.message, !message.isEmpty {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let entry = response.entry {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.title)
                            .font(.headline)
                        Text(entry.content)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("ID: \(entry.id)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                } else if let entries = response.entries, !entries.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(index + 1). \(entry.title)")
                                    .font(.subheadline.weight(.semibold))
                                Text(entry.content)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(4)
                            }
                            if index < entries.count - 1 {
                                Divider()
                            }
                        }
                    }
                } else {
                    Text("No memory entries returned.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .modifier(
                ResultBoxStyle(
                    backgroundColor: sectionBackgroundColor,
                    borderColor: sectionBorderColor
                )
            )
        } else {
            rawResultView(for: result)
        }
    }

    private var unavailableFormattedResultView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Formatted view unavailable")
                .font(.subheadline.weight(.semibold))
            Text("The tool returned data that can't be formatted. Switch to Raw to inspect the original response.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(
            ResultBoxStyle(
                backgroundColor: sectionBackgroundColor,
                borderColor: sectionBorderColor
            )
        )
    }

    @ViewBuilder
    private func pythonResultView(for result: String) -> some View {
        if let pythonResult = ToolCallViewSupport.parsePythonResult(from: result) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("Exit code: \(pythonResult.exitCode)")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            pythonResult.exitCode == 0
                                ? neutralPillBackgroundColor
                                : Color.red.opacity(0.12)
                        )
                        .clipShape(Capsule())
                    Text("\(pythonResult.executionTimeMs)ms")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if pythonResult.timedOut {
                        Text("TIMED OUT")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.red)
                    }
                }

                if !pythonResult.stdout.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Output")
                            .font(.caption.weight(.semibold))
                        ScrollView {
                            Text(pythonResult.stdout)
                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 200)
                        .padding(8)
                        .background(monospaceBackgroundColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(sectionBorderColor, lineWidth: 0.8)
                        )
                        .cornerRadius(8)
                    }
                }

                if !pythonResult.stderr.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Errors")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                        ScrollView {
                            Text(pythonResult.stderr)
                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                .foregroundStyle(.orange)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 150)
                        .padding(8)
                        .background(warningBackgroundColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(warningBorderColor, lineWidth: 0.8)
                        )
                        .cornerRadius(8)
                    }
                }

                if let error = pythonResult.error, !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .modifier(
                ResultBoxStyle(
                    backgroundColor: sectionBackgroundColor,
                    borderColor: sectionBorderColor
                )
            )
        } else {
            rawResultView(for: result)
        }
    }

    private func rawResultView(for result: String) -> some View {
        ScrollView {
            Text(ToolCallViewSupport.formatRawResult(result))
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .modifier(
            ResultBoxStyle(
                backgroundColor: monospaceBackgroundColor,
                borderColor: sectionBorderColor
            )
        )
    }
}

private struct ResultBoxStyle: ViewModifier {
    let backgroundColor: Color
    let borderColor: Color

    func body(content: Content) -> some View {
        content
            .frame(maxHeight: 300)
            .padding()
            .background(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(borderColor, lineWidth: 0.8)
            )
            .cornerRadius(8)
    }
}

enum ToolCallViewSupport {
    enum ToolKind: Equatable {
        case webSearch
        case python
        case memory
        case generic
    }

    enum ResultDisplayMode: String, CaseIterable, Hashable {
        case formatted
        case raw

        var title: String {
            rawValue.capitalized
        }
    }

    struct WebSearchResultItem: Equatable {
        let title: String
        let url: String
        let snippet: String
        let engine: String?
        let score: String?

        init?(dictionary: [String: Any]) {
            let rawTitle = (dictionary["title"] as? String) ?? (dictionary["name"] as? String) ?? ""
            let rawURL = (dictionary["url"] as? String) ?? (dictionary["link"] as? String) ?? ""
            let rawSnippet = (dictionary["snippet"] as? String)
                ?? (dictionary["summary"] as? String)
                ?? (dictionary["description"] as? String)
                ?? ""

            let normalizedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedSnippet = rawSnippet.trimmingCharacters(in: .whitespacesAndNewlines)

            if normalizedTitle.isEmpty && normalizedURL.isEmpty && normalizedSnippet.isEmpty {
                return nil
            }

            title = normalizedTitle
            url = normalizedURL
            snippet = normalizedSnippet
            engine = (dictionary["engine"] as? String) ?? (dictionary["source"] as? String)

            if let string = dictionary["score"] as? String {
                score = string
            } else if let number = dictionary["score"] as? NSNumber {
                score = number.stringValue
            } else if let bool = dictionary["score"] as? Bool {
                score = bool ? "true" : "false"
            } else if let string = dictionary["rank"] as? String {
                score = string
            } else if let number = dictionary["rank"] as? NSNumber {
                score = number.stringValue
            } else if let bool = dictionary["rank"] as? Bool {
                score = bool ? "true" : "false"
            } else {
                score = nil
            }
        }

        var displayTitle: String {
            title.isEmpty ? url : title
        }
    }

    struct ParameterSummaryEntry: Equatable, Identifiable {
        let key: String
        let value: String

        var id: String { key }
    }

    static func toolKind(for toolName: String) -> ToolKind {
        let normalizedToolName = toolName.lowercased()
        if normalizedToolName.contains("python") {
            return .python
        }
        if normalizedToolName.contains("memory") {
            return .memory
        }
        if normalizedToolName.contains("noema.web.retrieve")
            || normalizedToolName.contains("web")
            || normalizedToolName.contains("search") {
            return .webSearch
        }
        return .generic
    }

    static func defaultResultDisplayMode(toolName: String, result: String?) -> ResultDisplayMode {
        supportsFormattedResultDisplay(toolName: toolName, result: result) ? .formatted : .raw
    }

    static func supportsFormattedResultDisplay(toolName: String, result: String?) -> Bool {
        guard let result else { return false }

        switch toolKind(for: toolName) {
        case .python:
            return parsePythonResult(from: result) != nil
        case .memory:
            return parseMemoryResult(from: result) != nil
        case .webSearch:
            return !parseWebResults(from: result).isEmpty
        case .generic:
            return false
        }
    }

    static func isActiveWebSearch(toolName: String, phase: ChatVM.Msg.ToolCallPhase) -> Bool {
        toolKind(for: toolName) == .webSearch && phase.isInFlight
    }

    static func shouldAnimateCompletionSweep(toolName: String, phase: ChatVM.Msg.ToolCallPhase) -> Bool {
        phase == .completed && toolKind(for: toolName) == .generic
    }

    static func parsePythonResult(from result: String) -> PythonExecutionResult? {
        guard let data = result.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PythonExecutionResult.self, from: data)
    }

    static func parseWebResults(from result: String) -> [WebSearchResultItem] {
        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }

        var rawItems: [[String: Any]] = []

        if let array = json as? [[String: Any]] {
            rawItems = array
        } else if let dict = json as? [String: Any] {
            let candidateKeys = ["results", "items", "data", "hits", "entries"]
            for key in candidateKeys {
                if let array = dict[key] as? [[String: Any]] {
                    rawItems = array
                    break
                }
            }
            if rawItems.isEmpty, let array = dict["result"] as? [[String: Any]] {
                rawItems = array
            }
        }

        return rawItems.compactMap { WebSearchResultItem(dictionary: $0) }
    }

    static func parseMemoryResult(from result: String) -> MemoryToolResponse? {
        guard let data = result.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(MemoryToolResponse.self, from: data)
    }

    static func parameterSummaryEntries(
        from params: [String: AnyCodable],
        maxEntries: Int = 2,
        maxValueLength: Int = 50
    ) -> [ParameterSummaryEntry] {
        Array(params.keys.sorted().prefix(maxEntries)).map { key in
            let rawValue = String(describing: params[key]?.value ?? "")
            return ParameterSummaryEntry(
                key: key,
                value: String(rawValue.prefix(maxValueLength))
            )
        }
    }

    static func remainingParameterCount(from params: [String: AnyCodable], maxEntries: Int = 2) -> Int {
        max(0, params.count - maxEntries)
    }

    static func formatParameterValue(_ value: Any?) -> String {
        guard let value else { return "null" }

        if let string = value as? String {
            return string
        }
        if let dict = value as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
           let prettyString = String(data: data, encoding: .utf8) {
            return prettyString
        }
        if let array = value as? [Any],
           let data = try? JSONSerialization.data(withJSONObject: array, options: .prettyPrinted),
           let prettyString = String(data: data, encoding: .utf8) {
            return prettyString
        }

        return String(describing: value)
    }

    static func formatRawResult(_ result: String) -> String {
        if let data = result.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            return prettyString
        }
        return result
    }
}

private extension View {
    @ViewBuilder
    func toolCallDetailPresentation(
        isPresented: Binding<Bool>,
        toolCall: ChatVM.Msg.ToolCall
    ) -> some View {
        #if os(macOS)
        popover(isPresented: isPresented, arrowEdge: .top) {
            ToolCallDetailSheet(toolCall: toolCall)
                .toolCallDetailPopupPresentation()
        }
        #else
        sheet(isPresented: isPresented) {
            ToolCallDetailSheet(toolCall: toolCall)
                .toolCallDetailPopupPresentation()
        }
        #endif
    }

    @ViewBuilder
    func toolCallDetailPopupPresentation() -> some View {
        #if os(macOS)
        frame(minWidth: 560, minHeight: 520)
        #else
        self
        #endif
    }
}

private enum HTMLStripper {
    static let newlineRegex = try? NSRegularExpression(
        pattern: "<\\s*(br|/?p)\\b[^>]*>",
        options: [.caseInsensitive]
    )
    static let tagRegex = try? NSRegularExpression(
        pattern: "<[^>]+>",
        options: [.caseInsensitive]
    )
}

fileprivate extension String {
    func strippingHTMLTags() -> String {
        guard !isEmpty else { return self }

        var working = self

        if let newlineRegex = HTMLStripper.newlineRegex {
            let range = NSRange(location: 0, length: working.utf16.count)
            working = newlineRegex.stringByReplacingMatches(
                in: working,
                options: [],
                range: range,
                withTemplate: "\n"
            )
        }

        if let tagRegex = HTMLStripper.tagRegex {
            let range = NSRange(location: 0, length: working.utf16.count)
            working = tagRegex.stringByReplacingMatches(
                in: working,
                options: [],
                range: range,
                withTemplate: ""
            )
        }

        working = working.replacingOccurrences(
            of: "\n{3,}",
            with: "\n\n",
            options: .regularExpression
        )

        working = working.replacingOccurrences(
            of: " {2,}",
            with: " ",
            options: .regularExpression
        )

        working = working.decodingHTMLEntities()
        working = working.replacingOccurrences(of: "\u{00A0}", with: " ")

        return working.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decodingHTMLEntities() -> String {
        var decoded = self
        let namedEntities: [String: String] = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&nbsp;": "\u{00A0}"
        ]

        for (entity, replacement) in namedEntities {
            decoded = decoded.replacingOccurrences(of: entity, with: replacement)
        }

        func replacingMatches(pattern: String, transformer: (NSTextCheckingResult, String) -> String) -> String {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return decoded }
            let nsString = decoded as NSString
            let matches = regex.matches(in: decoded, options: [], range: NSRange(location: 0, length: nsString.length))
            var result = decoded
            for match in matches.reversed() {
                let replacement = transformer(match, decoded)
                let range = match.range
                let startIndex = result.index(result.startIndex, offsetBy: range.location)
                let endIndex = result.index(startIndex, offsetBy: range.length)
                result.replaceSubrange(startIndex..<endIndex, with: replacement)
            }
            return result
        }

        decoded = replacingMatches(pattern: "&#(\\d+);") { match, source in
            let nsSource = source as NSString
            let numberRange = match.range(at: 1)
            let numberString = nsSource.substring(with: numberRange)
            if let codePoint = Int(numberString), let scalar = UnicodeScalar(codePoint) {
                return String(scalar)
            }
            return nsSource.substring(with: match.range)
        }

        decoded = replacingMatches(pattern: "&#x([0-9A-Fa-f]+);") { match, source in
            let nsSource = source as NSString
            let hexRange = match.range(at: 1)
            let hexString = nsSource.substring(with: hexRange)
            if let codePoint = Int(hexString, radix: 16), let scalar = UnicodeScalar(codePoint) {
                return String(scalar)
            }
            return nsSource.substring(with: match.range)
        }

        return decoded
    }
}

#Preview {
    VStack(spacing: 16) {
        ToolCallView(toolCall: .init(
            toolName: "noema.web.retrieve",
            displayName: "Web Search",
            iconName: "globe",
            requestParams: [
                "query": AnyCodable("latest news on AI"),
                "count": AnyCodable(5),
                "safesearch": AnyCodable("moderate")
            ],
            result: """
            [{"title": "Breaking: New AI Model Released", "url": "https://example.com/ai-news", "snippet": "A groundbreaking new AI model has been released today..."},
             {"title": "AI Safety Research Update", "url": "https://example.com/safety", "snippet": "Latest developments in AI safety research show promising results..."}]
            """,
            error: nil
        ))

        ToolCallView(toolCall: .init(
            toolName: "noema.code.analyze",
            displayName: "Code Analysis",
            iconName: "curlybraces",
            requestParams: ["file": AnyCodable("main.swift"), "language": AnyCodable("swift")],
            result: nil,
            error: nil
        ))

        ToolCallView(toolCall: .init(
            toolName: "noema.web.retrieve",
            displayName: "Web Search",
            iconName: "globe",
            requestParams: ["query": AnyCodable("test query")],
            result: nil,
            error: "Network error: Connection failed"
        ))
    }
    .padding()
    .frame(maxWidth: .infinity)
    .background(Color(uiColor: .systemBackground))
}
