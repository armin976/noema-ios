import SwiftUI
import UIKit
import PhotosUI

struct MainShell: View {
    @EnvironmentObject private var experience: AppExperienceCoordinator
    @EnvironmentObject private var chatVM: ChatVM
    @EnvironmentObject private var modelManager: AppModelManager
    @EnvironmentObject private var datasetManager: DatasetManager
    @EnvironmentObject private var tabRouter: TabRouter
    @EnvironmentObject private var downloadController: DownloadController

    @State private var showSplash = true

    var body: some View {
        ZStack {
            SpacesSidebar {
                MainView()
                    .environmentObject(experience)
                    .environmentObject(chatVM)
                    .environmentObject(modelManager)
                    .environmentObject(datasetManager)
                    .environmentObject(tabRouter)
                    .environmentObject(downloadController)
            }

            if showSplash {
                SplashView()
                    .transition(.opacity)
            }
        }
        .fullScreenCover(isPresented: $experience.showOnboarding) {
            OnboardingView(showOnboarding: $experience.showOnboarding)
                .environmentObject(experience)
        }
        .sheet(isPresented: $experience.showShortcutHelp) {
            KeyboardShortcutCheatSheetView {
                experience.dismissShortcutHelp()
            }
        }
        .onAppear {
            print("[Noema] app launched 🚀")
            let isFirstLaunch = experience.isFirstLaunch
            if isFirstLaunch {
                experience.showOnboarding = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation {
                    showSplash = false
                }
                if isFirstLaunch {
                    experience.reopenOnboarding()
                }
            }
        }
    }
}

/// Hosts the main tabs with the default system tab bar.
private struct MainView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var experience: AppExperienceCoordinator
    @EnvironmentObject private var tabRouter: TabRouter
    @EnvironmentObject private var chatVM: ChatVM
    @EnvironmentObject private var modelManager: AppModelManager
    @EnvironmentObject private var datasetManager: DatasetManager
    @EnvironmentObject private var downloadController: DownloadController
    @AppStorage("offGrid") private var offGrid = false
    @AppStorage("defaultModelPath") private var defaultModelPath = ""
    @State private var didAutoLoad = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $tabRouter.selection) {
                ChatView()
                    .tag(MainTab.chat)
                    .environmentObject(chatVM)
                    .environmentObject(modelManager)
                    .environmentObject(datasetManager)
                    .environmentObject(tabRouter)
                    .environmentObject(downloadController)
                    .tabItem { Label("Chat", systemImage: "message.fill") }

                StoredView()
                    .tag(MainTab.stored)
                    .environmentObject(chatVM)
                    .environmentObject(modelManager)
                    .environmentObject(datasetManager)
                    .environmentObject(tabRouter)
                    .environmentObject(downloadController)
                    .tabItem { Label("Stored", systemImage: "externaldrive") }

                if !offGrid {
                    ExploreContainerView()
                        .tag(MainTab.explore)
                        .environmentObject(chatVM)
                        .environmentObject(modelManager)
                        .environmentObject(datasetManager)
                        .environmentObject(tabRouter)
                        .environmentObject(downloadController)
                        .tabItem { Label("Explore", systemImage: "safari") }
                }

                SettingsView()
                    .tag(MainTab.settings)
                    .environmentObject(chatVM)
                    .environmentObject(modelManager)
                    .environmentObject(tabRouter)
                    .environmentObject(downloadController)
                    .environmentObject(experience)
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }

            DownloadOverlay()
                .environmentObject(downloadController)
            AutoFlowHUD()
                .padding()
        }
        .overlay(alignment: .top) {
            IndexingNotificationView(datasetManager: datasetManager)
                .environmentObject(chatVM)
                .padding(.top, UIDevice.current.userInterfaceIdiom == .pad ? 60 : 8)
        }
        .overlay(alignment: .top) {
            ModelLoadingNotificationView(modelManager: modelManager, loadingTracker: chatVM.loadingProgressTracker)
                .padding(.top, UIDevice.current.userInterfaceIdiom == .pad ? 120 : 68)
        }
        .sheet(isPresented: $downloadController.showPopup) {
            DownloadListPopup()
                .environmentObject(downloadController)
        }
        .task { await autoLoad() }
        .onAppear {
            modelManager.bind(datasetManager: datasetManager)
            downloadController.configure(modelManager: modelManager, datasetManager: datasetManager)
            datasetManager.bind(downloadController: downloadController)
            chatVM.modelManager = modelManager
            chatVM.datasetManager = datasetManager
            chatVM.startSubscriptionCheckTimer()
            if let keys = UserDefaults.standard.array(forKey: "RollingThought.Keys") as? [String] {
                for key in keys {
                    let storageKey = "RollingThought." + key
                    if let existing = chatVM.rollingThoughtViewModels[key] {
                        existing.loadState(forKey: storageKey)
                    } else {
                        let vm = RollingThoughtViewModel()
                        vm.loadState(forKey: storageKey)
                        chatVM.rollingThoughtViewModels[key] = vm
                    }
                }
            }
        }
        .onChange(of: offGrid) { on in
            NetworkKillSwitch.setEnabled(on)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                Task { await AutoFlowOrchestrator.shared.post(.appBecameActive) }
            }
            if phase == .background {
                let keys = Array(chatVM.rollingThoughtViewModels.keys)
                UserDefaults.standard.set(keys, forKey: "RollingThought.Keys")
                for (key, vm) in chatVM.rollingThoughtViewModels {
                    vm.saveState(forKey: "RollingThought." + key)
                }
            }
        }
    }

    @MainActor
    private func autoLoad() async {
        guard !didAutoLoad else { return }
        didAutoLoad = true

        await RevenueCatManager.shared.refreshEntitlements()

        if UserDefaults.standard.bool(forKey: "bypassRAMLoadPending") {
            UserDefaults.standard.set(false, forKey: "bypassRAMLoadPending")
            modelManager.refresh()
            chatVM.loadError = "Previous model failed to load because it likely exceeded memory. Lower context size or choose a smaller model."
            return
        }

        guard !chatVM.modelLoaded, !chatVM.loading else { return }
        modelManager.refresh()
        guard !defaultModelPath.isEmpty,
              let m = modelManager.downloadedModels.first(where: { $0.url.path == defaultModelPath }) else { return }
        let s = modelManager.settings(for: m)
        UserDefaults.standard.set(true, forKey: "bypassRAMLoadPending")
        await chatVM.unload()
        if await chatVM.load(url: m.url, settings: s, format: m.format) {
            modelManager.updateSettings(s, for: m)
            modelManager.markModelUsed(m)
        } else {
            modelManager.loadedModel = nil
        }
        UserDefaults.standard.set(false, forKey: "bypassRAMLoadPending")
    }
}

/// Splash screen shown at launch with the app logo and a spinner.
private struct SplashView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 20) {
                Image("Noema")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                ProgressView()
                    .progressViewStyle(.circular)
            }
        }
    }
}

struct KeyboardShortcutCommands: Commands {
    @ObservedObject var experience: AppExperienceCoordinator

    var body: some Commands {
        CommandMenu("Workspace") {
            Button("New Chat") {
                NotificationCenter.default.post(name: .shortcutNewChat, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command])

            Button("Focus Composer") {
                NotificationCenter.default.post(name: .shortcutFocusComposer, object: nil)
            }
            .keyboardShortcut("k", modifiers: [.command])

            Button("Stop Response") {
                NotificationCenter.default.post(name: .shortcutStopGeneration, object: nil)
            }
            .keyboardShortcut(".", modifiers: [.command])

            Button("Keyboard Shortcuts…") {
                experience.presentShortcutHelp()
            }
            .keyboardShortcut("?", modifiers: [.command, .shift])
        }
    }
}

extension Notification.Name {
    static let shortcutNewChat = Notification.Name("noema.shortcut.newChat")
    static let shortcutFocusComposer = Notification.Name("noema.shortcut.focusComposer")
    static let shortcutStopGeneration = Notification.Name("noema.shortcut.stopGeneration")
}
// MARK: –– Chat UI ----------------------------------------------------------

/// Renders a single message. Any text between `<think>` tags is wrapped in a
/// collapsible box with rounded corners.
private struct MessageView: View {
    let msg: ChatVM.Msg
    @EnvironmentObject var vm: ChatVM
    @State private var expandedThinkIndices: Set<Int> = []
    @State private var showContext = false
    
    private func parse(_ text: String, toolCalls: [ChatVM.Msg.ToolCall]? = nil) -> [ChatVM.Piece] {
        // First parse code blocks
        let codeBlocks = ChatVM.parseCodeBlocks(text)
        
        // Then parse think tags within each text piece
        var finalPieces: [ChatVM.Piece] = []
        var toolCallIndex = 0 // Track which tool call we're currently processing
        
        for piece in codeBlocks {
            switch piece {
            case .code(let code, let lang):
                // Detect tool-call JSON/XML inside fenced code blocks and surface a tool placeholder instead
                var insertedToolFromCodeBlock = false
                let codeSub = code[...]
                var tmp = codeSub
                // 1) XML-style <tool_call> blocks inside code fences
                while let callTag = tmp.range(of: "<tool_call>") {
                    tmp = tmp[callTag.upperBound...]
                    if let end = tmp.range(of: "</tool_call>") {
                        tmp = tmp[end.upperBound...]
                    } else {
                        tmp = tmp[tmp.endIndex...]
                    }
                    finalPieces.append(ChatVM.Piece.tool(toolCallIndex))
                    if toolCalls != nil && toolCallIndex < (toolCalls?.count ?? 0) - 1 { toolCallIndex += 1 }
                    insertedToolFromCodeBlock = true
                }
                // 2) TOOL_CALL:/TOOL_RESULT markers inside code fences
                tmp = codeSub
                while let callRange = tmp.range(of: "TOOL_CALL:") {
                    tmp = tmp[callRange.upperBound...]
                    finalPieces.append(ChatVM.Piece.tool(toolCallIndex))
                    if toolCalls != nil && toolCallIndex < (toolCalls?.count ?? 0) - 1 { toolCallIndex += 1 }
                    insertedToolFromCodeBlock = true
                }
                // 3) Bare JSON tool-call object inside code fences
                tmp = codeSub
                var searchStart = tmp.startIndex
                scanJSONInCode: while let braceStart = tmp[searchStart...].firstIndex(of: "{") {
                    if let braceEnd = findMatchingBrace(in: tmp, startingFrom: braceStart) {
                        let candidate = tmp[braceStart...braceEnd]
                        if (candidate.contains("\"tool_name\"") || candidate.contains("\"name\"") || candidate.contains("\"tool\"")) &&
                           (candidate.contains("\"arguments\"") || candidate.contains("\"args\"")) {
                            finalPieces.append(ChatVM.Piece.tool(toolCallIndex))
                            if toolCalls != nil && toolCallIndex < (toolCalls?.count ?? 0) - 1 { toolCallIndex += 1 }
                            insertedToolFromCodeBlock = true
                            // Continue after this JSON object in case of multiple
                            searchStart = tmp.index(after: braceEnd)
                            continue scanJSONInCode
                        }
                        searchStart = tmp.index(after: braceEnd)
                        continue scanJSONInCode
                    } else {
                        break scanJSONInCode
                    }
                }
                if !insertedToolFromCodeBlock {
                    finalPieces.append(ChatVM.Piece.code(code, language: lang))
                }
            case .text(let t):
                // Parse think tags in text
                var rest = t[...]
                // Detect multiple inline tool_call blocks
                func appendTextWithThinks(_ segment: Substring) {
                    var tmp = segment
                    while let s = tmp.range(of: "<think>") {
                        if s.lowerBound > tmp.startIndex {
                            // Strip any stray closing tags in plain text
                            let beforeText = String(tmp[..<s.lowerBound]).replacingOccurrences(of: "</think>", with: "")
                            finalPieces.append(ChatVM.Piece.text(beforeText))
                        }
                        tmp = tmp[s.upperBound...]
                        if let e = tmp.range(of: "</think>") {
                            let inner = String(tmp[..<e.lowerBound])
                            // Sanitize nested or stray think markers inside the box content
                            let sanitizedInner = inner
                                .replacingOccurrences(of: "<think>", with: "")
                                .replacingOccurrences(of: "</think>", with: "")
                            finalPieces.append(ChatVM.Piece.think(sanitizedInner, done: true))
                            tmp = tmp[e.upperBound...]
                        } else {
                            let partial = String(tmp)
                                .replacingOccurrences(of: "<think>", with: "")
                                .replacingOccurrences(of: "</think>", with: "")
                            finalPieces.append(ChatVM.Piece.think(partial, done: false))
                            tmp = tmp[tmp.endIndex...]
                        }
                    }
                    if !tmp.isEmpty {
                        let trailingText = String(tmp).replacingOccurrences(of: "</think>", with: "")
                        finalPieces.append(ChatVM.Piece.text(trailingText))
                    }
                }
                while let callTag = rest.range(of: "<tool_call>") {
                    if callTag.lowerBound > rest.startIndex { appendTextWithThinks(rest[..<callTag.lowerBound]) }
                    rest = rest[callTag.upperBound...]
                    if let end = rest.range(of: "</tool_call>") {
                        rest = rest[end.upperBound...]
                    } else {
                        rest = rest[rest.endIndex...]
                    }
                    // Use the current tool call index and increment for next one
                    finalPieces.append(ChatVM.Piece.tool(toolCallIndex))
                    if toolCalls != nil && toolCallIndex < (toolCalls?.count ?? 0) - 1 {
                        toolCallIndex += 1
                    }
                }
                // Detect multiple TOOL_CALL markers
                while let callRange = rest.range(of: "TOOL_CALL:") {
                    if callRange.lowerBound > rest.startIndex { appendTextWithThinks(rest[..<callRange.lowerBound]) }
                    var after = rest[callRange.upperBound...]
                    if let nextResp = (after.range(of: "<tool_response>") ?? after.range(of: "TOOL_RESULT:")) {
                        rest = after[nextResp.lowerBound...]
                    } else if let nl = after.firstIndex(of: "\n") {
                        rest = after[nl...]
                    } else {
                        rest = rest[rest.endIndex...]
                    }
                    // Use the current tool call index and increment for next one
                    finalPieces.append(ChatVM.Piece.tool(toolCallIndex))
                    if toolCalls != nil && toolCallIndex < (toolCalls?.count ?? 0) - 1 {
                        toolCallIndex += 1
                    }
                }

                // Detect bare JSON tool call objects and hide them inline
                // Looks for a JSON object containing either "tool_name" or legacy "name" along with "arguments"
                var searchStart = rest.startIndex
                scanJSON: while let braceStart = rest[searchStart...].firstIndex(of: "{") {
                    let maybeEnd = findMatchingBrace(in: rest, startingFrom: braceStart)
                    if let braceEnd = maybeEnd {
                        let candidate = rest[braceStart...braceEnd]
                        if (candidate.contains("\"tool_name\"") || candidate.contains("\"name\"")) && candidate.contains("\"arguments\"") {
                            // Emit text before the JSON block
                            if braceStart > rest.startIndex { appendTextWithThinks(rest[..<braceStart]) }
                            // Skip over the JSON block and insert a tool box placeholder
                            let afterEnd = rest.index(after: braceEnd)
                            rest = rest[afterEnd...]
                            finalPieces.append(ChatVM.Piece.tool(toolCallIndex))
                            if toolCalls != nil && toolCallIndex < (toolCalls?.count ?? 0) - 1 {
                                toolCallIndex += 1
                            }
                            // Restart search at beginning of updated remainder
                            searchStart = rest.startIndex
                            continue scanJSON
                        }
                    } else {
                        // Incomplete JSON; if it looks like a tool call, show placeholder and hide the partial content
                        let hasNameKey = rest.range(of: "\"name\"")
                        let hasToolNameKey = rest.range(of: "\"tool_name\"")
                        let hasArgsKey = rest.range(of: "\"arguments\"")
                        if (hasNameKey != nil || hasToolNameKey != nil), let argsRange = hasArgsKey {
                            if (hasNameKey?.lowerBound ?? braceStart) >= braceStart || argsRange.lowerBound >= braceStart {
                                if braceStart > rest.startIndex { appendTextWithThinks(rest[..<braceStart]) }
                                // Drop everything after the braceStart for now (will be replaced as stream continues)
                                rest = rest[rest.endIndex...]
                                finalPieces.append(ChatVM.Piece.tool(toolCallIndex))
                                if toolCalls != nil && toolCallIndex < (toolCalls?.count ?? 0) - 1 {
                                    toolCallIndex += 1
                                }
                                break scanJSON
                            }
                        }
                        // Continue searching after this opening brace
                        searchStart = rest.index(after: braceStart)
                        continue scanJSON
                    }
                    // Continue searching after this opening brace if not matched
                    searchStart = rest.index(after: braceStart)
                }
                // Hide multiple tool_response blocks
                while let toolRange = rest.range(of: "<tool_response>") ?? rest.range(of: "TOOL_RESULT:") {
                    if toolRange.lowerBound > rest.startIndex { appendTextWithThinks(rest[..<toolRange.lowerBound]) }
                    if rest[toolRange].hasPrefix("<tool_response>") {
                        rest = rest[toolRange.upperBound...]
                        if let end = rest.range(of: "</tool_response>") {
                            rest = rest[end.upperBound...]
                        } else {
                            rest = rest[rest.endIndex...]
                        }
                    } else {
                        // TOOL_RESULT payload can be a JSON object or array; skip entire structure
                        rest = rest[toolRange.upperBound...]
                        var idx = rest.startIndex
                        while idx < rest.endIndex && rest[idx].isWhitespace { idx = rest.index(after: idx) }
                        if idx < rest.endIndex {
                            if rest[idx] == "[" {
                                if let close = findMatchingBracket(in: rest, startingFrom: idx) {
                                    rest = rest[rest.index(after: close)...]
                                } else {
                                    rest = rest[rest.endIndex...]
                                }
                            } else if rest[idx] == "{" {
                                if let close = findMatchingBrace(in: rest, startingFrom: idx) {
                                    rest = rest[rest.index(after: close)...]
                                } else {
                                    rest = rest[rest.endIndex...]
                                }
                            } else {
                                rest = rest[rest.endIndex...]
                            }
                        } else {
                            rest = rest[rest.endIndex...]
                        }
                    }
                    // Tool response doesn't increment the index since it's for the same tool call
                    finalPieces.append(ChatVM.Piece.tool(toolCallIndex))
                }
                // Preserve all think blocks (and sanitize inner content)
                while let s = rest.range(of: "<think>") {
                    if s.lowerBound > rest.startIndex {
                        let before = String(rest[..<s.lowerBound]).replacingOccurrences(of: "</think>", with: "")
                        finalPieces.append(ChatVM.Piece.text(before))
                    }
                    
                    rest = rest[s.upperBound...]
                    if let e = rest.range(of: "</think>") {
                        let inner = String(rest[..<e.lowerBound])
                            .replacingOccurrences(of: "<think>", with: "")
                            .replacingOccurrences(of: "</think>", with: "")
                        finalPieces.append(ChatVM.Piece.think(inner, done: true))
                        rest = rest[e.upperBound...]
                    } else {
                        let partial = String(rest)
                            .replacingOccurrences(of: "<think>", with: "")
                            .replacingOccurrences(of: "</think>", with: "")
                        finalPieces.append(ChatVM.Piece.think(partial, done: false))
                        rest = rest[rest.endIndex...]
                    }
                }
                if !rest.isEmpty {
                    let tail = String(rest).replacingOccurrences(of: "</think>", with: "")
                    finalPieces.append(ChatVM.Piece.text(tail))
                }
            case .think:
                // This shouldn't happen from parseCodeBlocks
                finalPieces.append(piece)
            case .tool(_):
                // Render-time handled via ToolCallView; skip here
                break
            }
        }
        
        return finalPieces
    }
    

        // MARK: - Text or List rendering
        @ViewBuilder
        private func renderTextOrList(_ t: String) -> some View {
            // Enhanced rendering:
            // - Headings: lines starting with "# ", "## ", "### ", etc. get larger fonts
            // - Bullets: single-character markers ('-', '*', '+', '•') render with a leading dot
            // - Math: each line still routes through MathRichText for LaTeX support
            let text = normalizeListFormatting(t)
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(text.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, rawLine in
                        let line = rawLine
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        if trimmed.isEmpty {
                            // Preserve paragraph gaps produced by normalizeListFormatting
                            Text("")
                        } else if let level = headingLevel(for: trimmed) {
                            let content = String(trimmed.drop(while: { $0 == "#" || $0 == " " }))
                            MathRichText(source: content, bodyFont: headingFont(for: level))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else if let (marker, content) = parseBulletLine(line) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(marker)
                                MathRichText(source: content)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            MathRichText(source: line)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }

        private func headingLevel(for line: String) -> Int? {
            // Recognize ATX-style headings: '#', '##', '###', up to 6
            guard line.first == "#" else { return nil }
            var count = 0
            for ch in line {
                if ch == "#" { count += 1 } else { break }
            }
            // Must have a space after hashes to be a heading
            if count >= 1 && count <= 6 {
                let idx = line.index(line.startIndex, offsetBy: count)
                if idx < line.endIndex && line[idx].isWhitespace { return count }
            }
            return nil
        }

        private func headingFont(for level: Int) -> Font {
            switch level {
            case 1: return .largeTitle
            case 2: return .title2
            case 3: return .title3
            default: return .headline
            }
        }

        // Normalizes inline lists like " ...  1. Item  2. Item ..." to place each
        // item on its own line. Our rich text engine preserves paragraph breaks
        // only for double newlines, so we emit "\n\n" here.
        private func normalizeListFormatting(_ text: String) -> String {
            var s = text
            func replace(_ pattern: String, _ template: String) {
                if let rx = try? NSRegularExpression(pattern: pattern) {
                    let range = NSRange(s.startIndex..<s.endIndex, in: s)
                    s = rx.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: template)
                }
            }
            // Insert paragraph break before inline numbered items like "  2.", "  3)" or "  4]"
            replace(#"(?<!\n)\s{1,}(?=\d{1,3}[\.\)\]]\s)"#, "\n\n")
            // Insert paragraph break before inline bullet markers like " - ", " * ", " + ", or " • "
            replace(#"(?<!\n)\s{1,}(?=[\-\*\+•]\s)"#, "\n\n")
            // Ensure a single newline before a list marker becomes a paragraph break
            replace(#"\n(?=\s*(?:\d{1,3}[\.\)\]]\s|[\-\*\+•]\s))"#, "\n\n")
            // If a list follows a colon, break the line after the colon
            replace(#":\s+(?=(?:\d{1,3}[\.\)\]]\s|[\-\*\+•]\s))"#, ":\n\n")
            // Collapse any 3+ consecutive newlines into a double newline
            replace(#"\n{3,}"#, "\n\n")
            return s
        }
    
    // MARK: - List parsing helpers
    private struct TextBlock {
        let content: String
        let isList: Bool
        let marker: String?
    }
    
    private func parseTextBlocks(_ text: String) -> [TextBlock] {
        var blocks: [TextBlock] = []
        let lines = text.components(separatedBy: .newlines)
        var currentTextBlock = ""
        
        for line in lines {
            if let (marker, content) = parseBulletLine(line) {
                // If we have accumulated text, add it as a text block
                if !currentTextBlock.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append(TextBlock(content: currentTextBlock, isList: false, marker: nil))
                    currentTextBlock = ""
                }
                // Add the list item
                blocks.append(TextBlock(content: content, isList: true, marker: marker))
            } else {
                // Accumulate non-list lines
                currentTextBlock += (currentTextBlock.isEmpty ? "" : "\n") + line
            }
        }
        
        // Add any remaining text
        if !currentTextBlock.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blocks.append(TextBlock(content: currentTextBlock, isList: false, marker: nil))
        }
        
        return blocks
    }
    
    private func parseListItems(_ text: String) -> [(marker: String, content: String)] {
        var items: [(String, String)] = []
        let lines = text.components(separatedBy: .newlines)
        
        for line in lines {
            if let item = parseBulletLine(line) {
                items.append(item)
            }
        }
        
        return items
    }
    
    private func parseBulletLine(_ line: String) -> (marker: String, content: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        
        // Unordered bullets: -, *, +, •
        if trimmed.hasPrefix("- ") { return ("•", String(trimmed.dropFirst(2))) }
        if trimmed.hasPrefix("* ") { return ("•", String(trimmed.dropFirst(2))) }
        if trimmed.hasPrefix("+ ") { return ("•", String(trimmed.dropFirst(2))) }
        if trimmed.hasPrefix("• ") { return ("•", String(trimmed.dropFirst(2))) }
        
        // Ordered bullets: 1. 2) 3]
        if let dotIdx = trimmed.firstIndex(of: "."), dotIdx > trimmed.startIndex {
            let prefix = String(trimmed[..<dotIdx])
            if Int(prefix) != nil, trimmed[dotIdx...].hasPrefix(". ") {
                return (prefix + ".", String(trimmed[trimmed.index(dotIdx, offsetBy: 2)...]))
            }
        }
        if let parenIdx = trimmed.firstIndex(of: ")"), parenIdx > trimmed.startIndex {
            let prefix = String(trimmed[..<parenIdx])
            if Int(prefix) != nil, trimmed[parenIdx...].hasPrefix(") ") {
                return (prefix + ")", String(trimmed[trimmed.index(parenIdx, offsetBy: 2)...]))
            }
        }
        if let bracketIdx = trimmed.firstIndex(of: "]"), bracketIdx > trimmed.startIndex {
            let prefix = String(trimmed[..<bracketIdx])
            if Int(prefix) != nil, trimmed[bracketIdx...].hasPrefix("] ") {
                return (prefix + "]", String(trimmed[trimmed.index(bracketIdx, offsetBy: 2)...]))
            }
        }
        
        return nil
    }
    
    private func extractRemainingText(from text: String, afterListItems items: [(String, String)]) -> String {
        var remaining = ""
        let lines = text.components(separatedBy: .newlines)
        
        for line in lines {
            if parseBulletLine(line) == nil {
                remaining += (remaining.isEmpty ? "" : "\n") + line
            }
        }
        
        return remaining
    }

    @AppStorage("isAdvancedMode") private var isAdvancedMode = false
    
    // MARK: - Code block rendering
    private struct CodeBlockView: View {
        let code: String
        let language: String?
        @State private var copied = false
        
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                // Header with language label and copy button
                HStack {
                    if let lang = language, !lang.isEmpty {
                        Text(lang)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: {
                        #if os(iOS)
                        UIPasteboard.general.string = code
                        #elseif os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
                        #endif
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            copied = false
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.caption)
                            Text(copied ? "Copied!" : "Copy")
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
                
                // Code content with darker background
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(.systemGray6))
                .adaptiveCornerRadius(.small)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .background(Color(.systemGray5))
            .adaptiveCornerRadius(.medium)
            .overlay(
                RoundedRectangle(cornerRadius: UIConstants.cornerRadius)
                    .stroke(Color(.systemGray4), lineWidth: 0.5)
            )
        }
    }

    // Helper to find matching closing brace for a JSON object, honoring strings and escapes
    private func findMatchingBrace(in text: Substring, startingFrom startIndex: Substring.Index) -> Substring.Index? {
        guard text[startIndex] == "{" else { return nil }
        var braceCount = 0
        var inString = false
        var escapeNext = false
        var idx = startIndex
        while idx < text.endIndex {
            let char = text[idx]
            if escapeNext {
                escapeNext = false
                idx = text.index(after: idx)
                continue
            }
            if char == "\\" && inString {
                escapeNext = true
                idx = text.index(after: idx)
                continue
            }
            if char == "\"" { inString.toggle() }
            if !inString {
                if char == "{" { braceCount += 1 }
                else if char == "}" {
                    braceCount -= 1
                    if braceCount == 0 { return idx }
                }
            }
            idx = text.index(after: idx)
        }
        return nil
    }

    // Helper to find matching closing bracket for a JSON array, honoring strings and escapes
    private func findMatchingBracket(in text: Substring, startingFrom startIndex: Substring.Index) -> Substring.Index? {
        guard text[startIndex] == "[" else { return nil }
        var depth = 0
        var inString = false
        var escapeNext = false
        var idx = startIndex
        while idx < text.endIndex {
            let char = text[idx]
            if escapeNext {
                escapeNext = false
                idx = text.index(after: idx)
                continue
            }
            if char == "\\" && inString {
                escapeNext = true
                idx = text.index(after: idx)
                continue
            }
            if char == "\"" { inString.toggle() }
            if !inString {
                if char == "[" { depth += 1 }
                else if char == "]" {
                    depth -= 1
                    if depth == 0 { return idx }
                }
            }
            idx = text.index(after: idx)
        }
        return nil
    }

    var bubbleColor: Color {
        msg.role == "🧑‍💻" ? Color.accentColor.opacity(0.2) : Color(.secondarySystemBackground)
    }

    @ViewBuilder
    private func imagesView(paths: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(paths.prefix(5).enumerated()), id: \.offset) { _, p in
                    if let ui = UIImage(contentsOfFile: p) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 96, height: 96)
                            .clipped()
                            .cornerRadius(12)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func webSearchSummaryView() -> some View {
        if let err = msg.webError {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                Text("Web search error: \(err)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(Color(.systemGray6))
            .adaptiveCornerRadius(.medium)
        } else if let hits = msg.webHits, !hits.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "globe").font(.caption)
                        Text("\(hits.count)")
                            .font(.caption2).bold()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray6))
                    .clipShape(Capsule())
                    ForEach(Array(hits.enumerated()), id: \.offset) { idx, h in
                        Button(action: { showContext = true }) {
                            HStack(spacing: 6) {
                                Text("\(idx+1)")
                                    .font(.caption2).bold()
                                Text(h.title.isEmpty ? h.url : h.title)
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color(.systemGray6))
                            .adaptiveCornerRadius(.small)
                        }
                        .buttonStyle(.plain)
                        .sheet(isPresented: Binding(get: { showContext }, set: { showContext = $0 })) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(h.title.isEmpty ? h.url : h.title).font(.headline)
                                        Text("Source: \(h.engine) · \(h.url)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Button("Close") { showContext = false }
                                }
                                ScrollView {
                                    Text(h.snippet)
                                        .font(.body)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.top, 4)
                                }
                                .frame(maxHeight: .infinity)
                            }
                            .padding()
                            .frame(minWidth: 300, minHeight: 200)
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
        } else {
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.8)
                Text("Searching the web…")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(Color(.systemGray6))
            .adaptiveCornerRadius(.medium)
        }
    }

    @ViewBuilder
    private func toolInlineView(index: Int) -> some View {
        if let calls = msg.toolCalls {
            let call: ChatVM.Msg.ToolCall? = calls.indices.contains(index) ? calls[index] : calls.last
            if let call = call {
                // For web search calls, ensure we have proper result/error state
                if call.toolName == "noema.web.retrieve" {
                    let updatedCall: ChatVM.Msg.ToolCall = {
                        if let err = msg.webError {
                            return ChatVM.Msg.ToolCall(
                                id: call.id,
                                toolName: call.toolName,
                                displayName: call.displayName,
                                iconName: call.iconName,
                                requestParams: call.requestParams,
                                result: nil,
                                error: err,
                                timestamp: call.timestamp
                            )
                        } else if let hits = msg.webHits, !hits.isEmpty {
                            // Convert web hits to JSON string for result
                            let hitsArray = hits.map { hit in
                                [
                                    "title": hit.title,
                                    "url": hit.url,
                                    "snippet": hit.snippet,
                                    "engine": hit.engine,
                                    "score": hit.score
                                ] as [String: Any]
                            }
                            if let data = try? JSONSerialization.data(withJSONObject: hitsArray, options: .prettyPrinted),
                               let jsonString = String(data: data, encoding: .utf8) {
                                return ChatVM.Msg.ToolCall(
                                    id: call.id,
                                    toolName: call.toolName,
                                    displayName: call.displayName,
                                    iconName: call.iconName,
                                    requestParams: call.requestParams,
                                    result: jsonString,
                                    error: nil,
                                    timestamp: call.timestamp
                                )
                            } else {
                                return call
                            }
                        } else {
                            return call
                        }
                    }()
                    ToolCallView(toolCall: updatedCall)
                } else {
                    ToolCallView(toolCall: call)
                }
            } else {
                EmptyView()
            }
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func piecesView(_ pieces: [ChatVM.Piece]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(pieces.enumerated()), id: \.offset) { idx, piece in
                let prevIsThink: Bool = {
                    if idx == 0 { return false }
                    if case .think(_, _) = pieces[idx - 1] { return true }
                    return false
                }()
                let prevIsTool: Bool = {
                    if idx == 0 { return false }
                    if case .tool(_) = pieces[idx - 1] { return true }
                    return false
                }()
                switch piece {
                case .text(let t):
                    if !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        renderTextOrList(t)
                            // Reduce padding when following thought or tool boxes
                            // so the final text sits closer to the preceding box.
                            .padding(.top, (prevIsThink || prevIsTool) ? 2 : 4)
                    }
                case .code(let code, let language):
                    CodeBlockView(code: code, language: language)
                        .padding(.top, 4)
                case .think(let t, let done):
                    let thinkOrdinalIndex: Int = {
                        var count = 0
                        for p in pieces.prefix(idx) {
                            if case .think(_, _) = p { count += 1 }
                        }
                        return count
                    }()
                    let thinkKey = "message-\(msg.id.uuidString)-think-\(thinkOrdinalIndex)"
                    if let viewModel = vm.rollingThoughtViewModels[thinkKey] {
                        RollingThoughtBox(viewModel: viewModel)
                            // Reduce gap after thought box so LaTeX-rendered boxes do not
                            // create excessive whitespace before subsequent text.
                            .padding(.top, prevIsTool ? 4 : 4)
                    } else {
                        // Avoid creating empty thought boxes which show "Waiting for thoughts..."
                        if !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            let tempVM = RollingThoughtViewModel()
                            RollingThoughtBox(viewModel: tempVM)
                                .padding(.top, prevIsTool ? 4 : 4)
                                .onAppear {
                                    // Defer publishing to next runloop tick to avoid mutating during view update
                                    DispatchQueue.main.async {
                                        tempVM.fullText = t
                                        tempVM.updateRollingLines()
                                        tempVM.phase = done ? .complete : .streaming
                                        if vm.rollingThoughtViewModels[thinkKey] == nil {
                                            vm.rollingThoughtViewModels[thinkKey] = tempVM
                                        }
                                    }
                                }
                        }
                    }
                case .tool(let index):
                    toolInlineView(index: index)
                        .padding(.top, prevIsThink ? 4 : 4)
                        .padding(.bottom, 2)
                }
            }
        }
    }

    var body: some View {
        // Pre-parse pieces to detect inline tool markers and avoid duplicating UI
        let pieces = parse(msg.text, toolCalls: msg.toolCalls)
        let hasInlineTool: Bool = pieces.contains { p in
            switch p { case .tool(_): return true; default: return false }
        }
        let hasWebRetrieveCall: Bool = (msg.toolCalls?.contains { $0.toolName == "noema.web.retrieve" } ?? false)
        VStack(alignment: msg.role == "🧑‍💻" ? .trailing : .leading, spacing: 2) {
            if let paths = msg.imagePaths, !paths.isEmpty { imagesView(paths: paths) }
            HStack {
                if msg.role == "🧑‍💻" { Spacer() }

                VStack(alignment: .leading, spacing: 4) {  // Reduced spacing from 8 to 4
                    // Generic tool calls (only if not already shown inline via parsed pieces)
                    // Always hide web search here so we use the dedicated summary box instead.
                    // Additionally, if we already have a dedicated web search summary, do not
                    // render a second generic ToolCallView for the same call to avoid duplicates.
                    if !hasInlineTool, let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {  // Reduced spacing from 8 to 4
                            ForEach(toolCalls.filter { call in
                                // Filter out web-search calls entirely when a web summary is present
                                if hasWebRetrieveCall || msg.usedWebSearch == true {
                                    return call.toolName != "noema.web.retrieve"
                                }
                                return true
                            }) { toolCall in
                                ToolCallView(toolCall: toolCall)
                            }
                        }
                        .padding(.bottom, 2)  // Small bottom padding to separate from following content
                    }
                    
                    // Web search callout (progress/results) when no inline tool UI
                    // Show as soon as we detect a web search tool call (JSON/XML),
                    // even if a placeholder ToolCall exists without inline markers.
                    if !hasInlineTool && (msg.usedWebSearch == true || hasWebRetrieveCall) {
                        // Keep the callout visible with stable spacing during streaming
                        webSearchSummaryView()
                            .padding(.bottom, 2)
                            .animation(.none, value: msg.text)
                    }
                    // Render parsed pieces in order with stable indices to avoid duplicate ID warnings
                    piecesView(pieces)
                }
                .padding(12)
                // Limit bubble width to 60% of the screen,
                // anchored from the sender's side
                .frame(
                    maxWidth: UIScreen.main.bounds.width * 0.85,
                    alignment: msg.role == "🧑‍💻" ? .trailing : .leading
                )
                .background(bubbleColor)
                .adaptiveCornerRadius(.large)
                .shadow(color: Color.black.opacity(0.1), radius: 1, x: 0, y: 1)
                if msg.role != "🧑‍💻" { Spacer() }
            }

            if isAdvancedMode, msg.role == "🤖", let p = msg.perf {
                let text = String(format: "%.2f tok/sec · %d tokens · %.2fs to first token", p.avgTokPerSec, p.tokenCount, p.timeToFirst)
                Text(text)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(msg.role == "🧑‍💻" ? .trailing : .leading, 12)
            }

            Text(msg.timestamp, style: .time)
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(msg.role == "🧑‍💻" ? .trailing : .leading, 12)

            if let citations = msg.citations, !citations.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text.magnifyingglass").font(.caption)
                            Text("\(citations.count)")
                                .font(.caption2).bold()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray6))
                        .clipShape(Capsule())
                        ForEach(Array(citations.enumerated()), id: \.offset) { idx, citation in
                            CitationButton(index: idx + 1, text: citation.text, source: citation.source)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .padding(msg.role == "🧑‍💻" ? .trailing : .leading, 12)
            } else if let ctx = msg.retrievedContext, !ctx.isEmpty {
                // Fallback for legacy messages without detailed citations
                let parts = ctx
                    .components(separatedBy: "\n\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text.magnifyingglass").font(.caption)
                            Text("\(parts.count)")
                                .font(.caption2).bold()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray6))
                        .clipShape(Capsule())
                        ForEach(Array(parts.enumerated()), id: \.offset) { idx, t in
                            CitationButton(index: idx + 1, text: t, source: nil)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .padding(msg.role == "🧑‍💻" ? .trailing : .leading, 12)
            }
        }
    }

struct ChatView: View {
    @EnvironmentObject var vm: ChatVM
    @EnvironmentObject var modelManager: AppModelManager
    @EnvironmentObject var datasetManager: DatasetManager
    @EnvironmentObject var tabRouter: TabRouter
    @FocusState private var inputFocused: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var notebookStore = NotebookStore()
    @State private var showNotebookSheet = false
    @State private var showSidebar = false
    @State private var showPercent = false
    @AppStorage("defaultModelPath") private var defaultModelPath = ""
    @State private var sessionToDelete: ChatVM.Session?
    @State private var shouldAutoScrollToBottom: Bool = true
    // Suggestion overlay state
    @State private var suggestionTriplet: [String] = ChatSuggestions.nextThree()
    @State private var suggestionsSessionID: UUID?


    private struct ChatInputBox: View {
        @Binding var text: String
        var focus: FocusState<Bool>.Binding
        let send: () -> Void
        let stop: () -> Void
        let canStop: Bool
        @EnvironmentObject var vm: ChatVM
        @State private var pickerItems: [PhotosPickerItem] = []
        @State private var showSmallCtxAlert: Bool = false


        var body: some View {
            HStack(spacing: 8) {
                WebSearchButton()
                VStack(spacing: 8) {
                    // Images displayed above the text field
                    if UIConstants.showMultimodalUI && vm.supportsImageInput && !vm.pendingImageURLs.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(vm.pendingImageURLs.prefix(5).enumerated()), id: \.offset) { idx, url in
                                    if let ui = UIImage(contentsOfFile: url.path) {
                                        ZStack(alignment: .topTrailing) {
                                            Image(uiImage: ui)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 80, height: 80)
                                                .clipped()
                                                .cornerRadius(12)
                                            Button(action: { vm.removePendingImage(at: idx) }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.white)
                                                    .font(.system(size: 16))
                                                    .background(Color.black.opacity(0.6))
                                                    .clipShape(Circle())
                                            }
                                            .accessibilityLabel("Remove image \(idx + 1)")
                                            .accessibilityHint("Removes the selected image from your message.")
                                            .offset(x: 6, y: -6)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: UIConstants.largeCornerRadius, style: .continuous)
                                .fill(Color(.systemGray6))
                        )
                    }
                    
                    // Input area with photo picker and text field
                    HStack(spacing: 12) {
                        if UIConstants.showMultimodalUI && vm.supportsImageInput {
                            PhotosPicker(selection: $pickerItems, maxSelectionCount: max(0, 5 - vm.pendingImageURLs.count), matching: .images) {
                                Image(systemName: "photo.on.rectangle")
                                    .font(.system(size: 18, weight: .semibold))
                                    .padding(10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(Color(.systemBackground))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                                    )
                                    .accessibilityLabel("Add image from Photos")
                            }
                            .onChange(of: pickerItems) { _, items in
                                Task { await loadPickedItems(items) }
                            }
                        }

                        TextField("Ask…", text: $text, axis: .vertical)
                            .lineLimit(1...5)
                            .focused(focus)
                            .submitLabel(.send)
                            .accessibilityLabel("Message input")
                            .accessibilityHint("Type what you want to ask the model.")
                            .onSubmit {
                                if UIConstants.showMultimodalUI && vm.supportsImageInput && !vm.pendingImageURLs.isEmpty && vm.contextLimit < 5000 {
                                    showSmallCtxAlert = true
                                } else {
                                    send()
                                    text = ""
                                }
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: UIConstants.largeCornerRadius, style: .continuous)
                                    .fill(Color(.systemBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: UIConstants.largeCornerRadius, style: .continuous)
                                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                            )
                            .frame(maxWidth: .infinity)
                    }
                }
                if canStop {
                    Button(action: stop) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.red)
                            )
                            .foregroundColor(.white)
                    }
                    .accessibilityLabel("Stop response")
                    .accessibilityHint("Cancel the current generation.")
                    .keyboardShortcut(.escape, modifiers: [])
                } else {
                    Button(action: {
                        if UIConstants.showMultimodalUI && vm.supportsImageInput && !vm.pendingImageURLs.isEmpty && vm.contextLimit < 5000 {
                            showSmallCtxAlert = true
                            return
                        }
                        send()
                        text = ""
                    }) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.accentColor)
                            )
                            .foregroundColor(.white)
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Send message")
                    .accessibilityHint("Submit your message to the assistant.")
                    .keyboardShortcut(.return, modifiers: [.command])
                }
            }
            .animation(.default, value: text)
            .alert("Small context may cause image crash", isPresented: $showSmallCtxAlert) {
                Button("Send Anyway") {
                    send()
                    text = ""
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Context length is under 5000 tokens. With images and multi-sequence decoding (n_seq_max=16), per-sequence memory can be too small, leading to a crash. Increase context to at least 8192 in Model Settings.")
            }
        }

        private func loadPickedItems(_ items: [PhotosPickerItem]) async {
            guard vm.supportsImageInput, !items.isEmpty else { return }
            let room = max(0, 5 - vm.pendingImageURLs.count)
            for item in items.prefix(room) {
                if let data = try? await item.loadTransferable(type: Data.self), let ui = UIImage(data: data) {
                    await vm.savePendingImage(ui)
                }
            }
            await MainActor.run { pickerItems.removeAll() }
        }
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                HStack(spacing: 0) {
                    chatNavigation
                    Divider()
                    NavigationStack {
                        NotebookView(store: notebookStore, onRunCode: runNotebookCell)
                            .navigationTitle("Notebook")
                    }
                    .frame(minWidth: 320, idealWidth: 380, maxWidth: 460)
                }
            } else {
                chatNavigation
                    .sheet(isPresented: $showNotebookSheet) {
                        NavigationStack {
                            NotebookView(store: notebookStore, onRunCode: runNotebookCell)
                                .navigationTitle("Notebook")
                                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showNotebookSheet = false } } }
                        }
                    }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pythonExecutionDidComplete)) { note in
            guard let result = note.object as? PythonExecuteResult else { return }
            Task { @MainActor in
                notebookStore.apply(pythonResult: result)
            }
        }
    }

    private var chatNavigation: some View {
        NavigationStack {
            ZStack(alignment: .leading) {
                chatContent
                if showSidebar {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture { withAnimation { showSidebar = false } }
                    sidebar
                        .frame(width: UIScreen.main.bounds.width * 0.48)
                        .transition(.move(edge: .leading))
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        withAnimation { showSidebar.toggle() }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                    .accessibilityLabel("Toggle chat list")
                    .accessibilityHint("Show or hide your recent conversations.")
                }
                ToolbarItem(placement: .principal) {
                    modelHeader
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if horizontalSizeClass == .compact {
                        Button { showNotebookSheet = true } label: { Image(systemName: "square.and.pencil") }
                            .accessibilityLabel("Open notebook")
                            .accessibilityHint("Review or edit the current notebook.")
                    }
                    Button { vm.startNewSession() } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Start new chat")
                        .accessibilityHint("Creates a fresh conversation.")
                        .keyboardShortcut("n", modifiers: [.command])
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert(item: $datasetManager.embedAlert) { info in
            Alert(title: Text(info.message))
        }
        .onReceive(NotificationCenter.default.publisher(for: .shortcutNewChat)) { _ in
            vm.startNewSession()
        }
        .onReceive(NotificationCenter.default.publisher(for: .shortcutFocusComposer)) { _ in
            withAnimation { showSidebar = false }
            inputFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .shortcutStopGeneration)) { _ in
            vm.stop()
        }
        .overlay(alignment: .top) {
            if let active = modelManager.activeDataset,
               datasetManager.indexingDatasetID == active.datasetID {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    let status = datasetManager.processingStatus[active.datasetID]
                    if let s = status, s.stage != .completed {
                        let etaStr: String = {
                            if let e = s.etaSeconds, e > 0 { return String(format: "~%dm %02ds", Int(e)/60, Int(e)%60) }
                            return "…"
                        }()
                        Text("Indexing: \(Int(s.progress * 100))% · \(etaStr)").font(.caption2)
                    } else {
                        Text("Indexing dataset…").font(.caption2)
                    }
                }
                .padding(8)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding()
            }
        }
    }

    private func runNotebookCell(code: String) {
        Task { await vm.sendMessage(code) }
    }

    private var chatContent: some View {
        return VStack {
            if let ds = modelManager.activeDataset, vm.currentModelFormat != .slm {
                // Modern dataset indicator pill
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.caption)
                        Text("Using \(ds.name)")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.blue.gradient)
                    )
                    .shadow(color: Color.blue.opacity(0.3), radius: 4, x: 0, y: 2)
                    
                    Spacer()
                }
                .padding(.horizontal, UIConstants.defaultPadding)
                .padding(.vertical, 8)
                
                // Show overlay only while deciding, or for full-content injection.
                // Hide it for Smart Retrieval so the Chain-of-Thought think tags are visible immediately.
                if vm.injectionStage == .deciding || (vm.injectionMethod == .full && vm.injectionStage != .none) {
                    HStack {
                        HStack(spacing: 8) {
                            if vm.injectionStage == .deciding {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.white)
                                Text("Analyzing context...")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                let methodText = vm.injectionMethod == .full ? "Full Content" : 
                                               vm.injectionMethod == .rag ? "Smart Retrieval" : "Processing"
                                Text(methodText)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(LinearGradient(
                                    colors: vm.injectionStage == .deciding ? 
                                           [Color.orange, Color.orange.opacity(0.8)] :
                                           [Color.green, Color.green.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ))
                        )
                        .shadow(color: vm.injectionStage == .deciding ? 
                               Color.orange.opacity(0.3) : Color.green.opacity(0.3), 
                               radius: 4, x: 0, y: 2)
                        
                        Spacer()
                    }
                    .padding(.horizontal, UIConstants.defaultPadding)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: vm.injectionStage)
                }
            }

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(vm.msgs.filter { $0.role != "system" }) { m in
                        MessageView(msg: m)
                            .id(m.id)
                    }
                }
                .padding()
                .padding(.bottom, 80)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture().onChanged { _ in shouldAutoScrollToBottom = false })
            // Centered suggestions overlay for brand-new empty chats
            .overlay(alignment: .center) {
                let isEmptyChat = vm.msgs.first(where: { $0.role != "system" }) == nil
                if isEmptyChat && !vm.isStreaming && !vm.loading {
                    SuggestionsOverlay(
                        suggestions: suggestionTriplet,
                        enabled: vm.modelLoaded,
                        onTap: { text in
                            guard vm.modelLoaded else { return }
                            suggestionTriplet = []
                            Task { await vm.sendMessage(text) }
                        }
                    )
                    .transition(.opacity.combined(with: .scale))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !shouldAutoScrollToBottom && vm.isStreaming {
                    Button {
                        if let id = vm.msgs.last?.id {
                            withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                        }
                        shouldAutoScrollToBottom = true
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.caption)
                            .padding(10)
                            .background(.thinMaterial)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Scroll to latest message")
                    .accessibilityHint("Jump to the bottom of the conversation.")
                    .padding(.trailing, 16)
                    .padding(.bottom, 96)
                }
            }
            .onTapGesture {
                inputFocused = false
                hideKeyboard()
            }
            .onReceive(NotificationCenter.default.publisher(for: .thinkToggled)) { note in
                guard let info = note.userInfo,
                      let idStr = info["messageId"] as? String,
                      let uuid = UUID(uuidString: idStr) else { return }
                // Scroll to the message that had its think box closed
                withAnimation {
                    proxy.scrollTo(uuid, anchor: .top)
                }
            }
            .onChange(of: vm.msgs) { _, msgs in
                if shouldAutoScrollToBottom, let id = msgs.last?.id {
                    withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            .onAppear {
                // Pick suggestions when entering a new empty chat (only once)
                let isEmpty = vm.msgs.first(where: { $0.role != "system" }) == nil
                if isEmpty && suggestionTriplet.isEmpty {
                    suggestionTriplet = ChatSuggestions.nextThree()
                    suggestionsSessionID = vm.activeSessionID
                }
            }
            .onChange(of: vm.activeSessionID) { _, newID in
                // Rotate suggestions per new session if starting empty
                let isEmpty = vm.msgs.first(where: { $0.role != "system" }) == nil
                if isEmpty && newID != suggestionsSessionID {
                    suggestionTriplet = ChatSuggestions.nextThree()
                    suggestionsSessionID = newID
                }
            }

        }
        let isIndexing = datasetManager.indexingDatasetID != nil
        ChatInputBox(text: $vm.prompt, focus: $inputFocused,
                     send: { let text = vm.prompt; vm.prompt = ""; Task { await vm.sendMessage(text) } },
                     stop: { vm.stop() },
                     canStop: vm.isStreaming)
        .disabled(!vm.modelLoaded || isIndexing)
        .opacity(vm.modelLoaded && !isIndexing ? 1 : 0.6)
        .padding()
        if isIndexing {
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.8)
                    Text("Dataset indexing in progress...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Chat will be available when indexing completes")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom)
        }
        }
        .alert("Load Failed", isPresented: Binding(get: { vm.loadError != nil }, set: { _ in vm.loadError = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.loadError ?? "")
        }
    }

    private var modelHeader: some View {
        Group {
            if let loaded = modelManager.loadedModel {
                HStack(spacing: 8) {
                    Text(loaded.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        modelManager.loadedModel = nil
                        Task { await vm.unload() }
                    }) {
                        Image(systemName: "eject")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(6)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Unload model")
                    .accessibilityHint("Disconnects the current model from the chat.")
                    Text(showPercent ?
                         "\(Int(Double(vm.totalTokens) / vm.contextLimit * 100)) %" :
                         "\(vm.totalTokens) tok")
                        .font(.caption2)
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                        .foregroundColor(.secondary)
                        .onTapGesture { showPercent.toggle() }
                }
            } else {
                Text("No model")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var sidebar: some View {
        return VStack(alignment: .leading) {
            HStack {
                Text("Recent Chats").font(.headline)
                Spacer()
                Button(action: { vm.startNewSession() }) { Image(systemName: "plus") }
                .accessibilityLabel("Start new chat")
                .accessibilityHint("Creates a fresh conversation.")
                .keyboardShortcut("n", modifiers: [.command])
            }
            .padding()
            List(selection: $vm.activeSessionID) {
                ForEach(vm.sessions) { session in
                    HStack {
                        Image(systemName: session.isFavorite ? "star.fill" : "message")
                        Text(session.title)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        vm.select(session)
                        withAnimation { showSidebar = false }
                    }
                    .contextMenu {
                        Button(session.isFavorite ? "Unfavorite" : "Favorite") { vm.toggleFavorite(session) }
                        Button(role: .destructive) { sessionToDelete = session } label: { Text("Delete") }
                    }
                    .swipeActions {
                        Button(role: .destructive) { sessionToDelete = session } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
            .listStyle(.plain)
            .confirmationDialog("Delete chat \(sessionToDelete?.title ?? "")?", isPresented: Binding(get: { sessionToDelete != nil }, set: { if !$0 { sessionToDelete = nil } })) {
                Button("Delete", role: .destructive) { if let s = sessionToDelete { vm.delete(s); sessionToDelete = nil } }
                Button("Cancel", role: .cancel) { sessionToDelete = nil }
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }


}

// MARK: - Citation UI
private struct SuggestionsOverlay: View {
    let suggestions: [String]
    let enabled: Bool
    let onTap: (String) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image("Noema")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .opacity(0.9)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                ForEach(suggestions.prefix(3), id: \.self) { s in
                    Button(action: { if enabled { onTap(s) } }) {
                        Text(s)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                            .frame(maxWidth: 520)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.systemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
                    .padding(.horizontal)
                    .disabled(!enabled)
                    .opacity(enabled ? 1.0 : 0.6)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
        .padding(.bottom, 40)
    }
}

private struct CitationButton: View {
    let index: Int
    let text: String
    let source: String?
    @State private var show = false

    var body: some View {
        Button(action: { show = true }) {
            HStack(spacing: 4) {
                Image(systemName: "book")
                    .font(.caption)
                Text("\(index)")
                    .font(.caption2).bold()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.systemGray6))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $show) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Citation \(index)").font(.headline)
                        if let source = source {
                            Text("Source: \(source)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Button("Close") { show = false }
                }
                ScrollView {
                    MathRichText(source: text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                .frame(maxHeight: .infinity)
            }
            .padding()
            .frame(minWidth: 300, minHeight: 200)
        }
    }

// Helper functions for global indexing overlay
private func globalStageColor(_ stage: DatasetProcessingStage, current: DatasetProcessingStage) -> Color {
    switch (stage, current) {
    case (.extracting, .extracting), (.compressing, .compressing), (.embedding, .embedding):
        return .blue
    case (.extracting, .compressing), (.extracting, .embedding), (.compressing, .embedding):
        return .green
    default:
        return .gray.opacity(0.3)
    }
}

private func globalStageLabel(_ stage: DatasetProcessingStage) -> String {
    switch stage {
    case .extracting: return "Extracting"
    case .compressing: return "Compressing"
    case .embedding: return "Embedding"
    case .completed: return "Ready"
    case .failed: return "Failed"
    }
}
