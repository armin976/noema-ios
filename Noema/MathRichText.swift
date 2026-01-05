// MathRichText.swift
//  MathRichText.swift
//  Noema
//
//  Renders mixed text with inline and block LaTeX using MathTokenizer and
//  SwiftMath-backed views. Keeps baseline alignment for inline math and flows
//  across lines.

import SwiftUI
import Foundation

struct MessageHoverCopySuppressionKey: EnvironmentKey {
    static let defaultValue: Binding<Bool>? = nil
}

extension EnvironmentValues {
    var messageHoverCopySuppression: Binding<Bool>? {
        get { self[MessageHoverCopySuppressionKey.self] }
        set { self[MessageHoverCopySuppressionKey.self] = newValue }
    }
}
#if os(macOS)
import AppKit
#endif

struct MathRichText: View {
    let source: String
    var bodyFont: Font = .body

    var body: some View {
        RichMathTextLabel(source: source, bodyFont: bodyFont)
            // VoiceOver was focusing on every tiny fragment because the composed
            // view tree breaks text into many subviews. Combine/override so the
            // whole paragraph is a single readable element.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityString)
    }

    private var accessibilityString: String {
        // Flatten excessive whitespace so the spoken output is natural.
        source.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}

private struct RichMathTextLabel: View {
    let source: String
    var bodyFont: Font
    private var blockFontSize: CGFloat {
#if os(macOS)
        // Chat messages use the platform body size as the baseline. Scale block display
        // math noticeably larger so $$ ... $$ content stands out relative to prose.
        return preferredFontSize(.body) * 1.5
#else
        return preferredFontSize(.title3)
#endif
    }

    var body: some View {
        enum Segment { case inline([MathToken]); case block(String); case incomplete(String) }
        let tokens = MathTokenizer.tokenize(source)
        let segments: [Segment] = {
            var out: [Segment] = []
            var currentInline: [MathToken] = []

            func flushInline() {
                if !currentInline.isEmpty {
                    out.append(.inline(currentInline))
                    currentInline.removeAll(keepingCapacity: true)
                }
            }

            for t in tokens {
                switch t {
                case .block(let latex):
                    flushInline()
                    out.append(.block(latex))

                case .inline:
                    currentInline.append(t)

                case .incomplete(let s):
                    // Flush any inline content first, then record incomplete LaTeX
                    flushInline()
                    out.append(.incomplete(s))

                case .text(let s):
                    if s.isEmpty { continue }
                    // Treat single newlines as soft spaces so inline math does not
                    // force awkward line breaks (e.g., when models add stray \n).
                    // Preserve paragraph breaks only for 2+ consecutive newlines.
                    let normalized = s.replacingOccurrences(of: "\r\n", with: "\n")
                    let paragraphs = normalized.components(separatedBy: "\n\n")
                    for (idx, para) in paragraphs.enumerated() {
                        let inlinePara = para.replacingOccurrences(of: "\n", with: " ")
                        if !inlinePara.isEmpty {
                            let split = MathTokenizer.splitHeuristicInlineLatex(in: inlinePara)
                            if split.isEmpty {
                                currentInline.append(.text(inlinePara))
                            } else {
                                currentInline.append(contentsOf: split)
                            }
                        }
                        if idx < paragraphs.count - 1 { flushInline() }
                    }
                }
            }
            flushInline()
            return out
        }()

        let view = VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                switch seg {
                case .inline(let inlineTokens):
                    InlineLine(tokens: inlineTokens, bodyFont: bodyFont)
                case .block(let latex):
#if os(macOS)
                    MacLatexHoverCopy(latex: latex) {
                        BlockMathView(latex: latex, fontSize: blockFontSize)
                    }
#else
                    BlockMathView(latex: latex, fontSize: blockFontSize)
#endif
                case .incomplete(let raw):
                    Text(raw)
                        .foregroundStyle(Color.red)
                }
            }
        }

#if os(macOS)
        return view.textSelection(.enabled)
#else
        return view
#endif
    }
}

private struct InlineLine: View {
    let tokens: [MathToken]
    var bodyFont: Font
    @ScaledMetric(wrappedValue: preferredFontSize(.body), relativeTo: .body) private var inlineSize: CGFloat

    init(tokens: [MathToken], bodyFont: Font) {
        self.tokens = tokens
        self.bodyFont = bodyFont
#if os(macOS)
        let baseSize = preferredFontSize(.body) * 1.4
#else
        let baseSize = preferredFontSize(.body)
#endif
        _inlineSize = ScaledMetric(wrappedValue: baseSize, relativeTo: .body)
    }

    var body: some View {
        // Wrap inline runs naturally across lines using Text + inline images/views
        // We compose as HStack with text wrapping via flexible Text segments
        // and InlineMathView kept small enough to fit within line height.
        // SwiftUI doesn't allow inline baseline directly in Text; we approximate with alignment guides.
        // We split consecutive text tokens to reduce view count.
        let runs = mergeText(tokens)
        WrappedInline(runs: runs, font: bodyFont, fontSize: inlineSize)
    }

    private func mergeText(_ tokens: [MathToken]) -> [MathToken] {
        var out: [MathToken] = []
        for t in tokens {
            switch t {
            case .text(let s):
                if case .text(let prev)? = out.last {
                    out.removeLast()
                    out.append(.text(prev + s))
                } else { out.append(.text(s)) }
            default:
                out.append(t)
            }
        }
        return out
    }
}

#if os(macOS)
private struct MacLatexHoverCopy<Content: View>: View {
    let latex: String
    let content: () -> Content
    @State private var isHovering = false
    @State private var copied = false
    @Environment(\.messageHoverCopySuppression) private var messageHoverCopySuppression

    var body: some View {
        content()
            .overlay(alignment: .topTrailing) {
                if isHovering {
                    Button(action: copyLatexToPasteboard) {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12, weight: .semibold))
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .foregroundStyle(Color.accentColor)
                            .background(.thinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .transition(.opacity.combined(with: .scale))
                    .accessibilityLabel("Copy LaTeX")
                }
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.16)) {
                    isHovering = hovering
                }
                messageHoverCopySuppression?.wrappedValue = hovering
                if !hovering {
                    copied = false
                }
            }
    }

    private func copyLatexToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(latex, forType: .string)
        withAnimation(.easeInOut(duration: 0.16)) {
            copied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeInOut(duration: 0.2)) {
                copied = false
            }
        }
    }
}
#endif

private struct WrappedInline: View {
    let runs: [MathToken]
    let font: Font
    let fontSize: CGFloat

    // Split text into small fragments at whitespace and punctuation boundaries
    // so punctuation isn't glued to words (which can cause unwanted wrapping
    // after inline LaTeX). This lets commas or periods remain with the
    // preceding word when there's room.
    private func splitFragments(_ s: String) -> [String] {
        guard !s.isEmpty else { return [] }
        let punctuation: Set<Character> = [",", ".", ";", ":", "!", "?", "-", "—", "–", ")", "]", "}", "\"", "'"]
        let openers: Set<Character> = ["(", "[", "{"]
        var frags: [String] = []
        var current = ""
        enum Kind { case space, other }
        func kind(of ch: Character) -> Kind { ch.isWhitespace ? .space : .other }
        var lastKind: Kind? = nil
        for ch in s {
            // Attach closing punctuation to the previous token to avoid starting
            // a new line with "," or "." after an inline formula.
            if punctuation.contains(ch) && !current.isEmpty {
                current.append(ch)
                lastKind = .other
                continue
            }
            // If an opener follows a space, start a new fragment so it can stick
            // to the following word on the same line.
            if openers.contains(ch) {
                if !current.isEmpty { frags.append(current) }
                current = String(ch)
                lastKind = .other
                continue
            }
            let k = kind(of: ch)
            if let lk = lastKind, lk != k {
                if !current.isEmpty { frags.append(current) }
                current = String(ch)
            } else {
                current.append(ch)
            }
            lastKind = k
        }
        if !current.isEmpty { frags.append(current) }
        return frags
    }

    // Convert to inline-only Markdown attributed fragments while respecting the
    // same wrapping boundaries as splitFragments.
    private func splitMarkdownFragments(_ s: String) -> [AttributedString] {
        guard !s.isEmpty else { return [] }
        func normalizeInlineSpacing(_ s: String) -> String {
            // Remove stray spaces before common punctuation the models often emit
            // (" ," -> ",") so commas don't wrap onto their own lines.
            var t = s
            let punct = [",", ".", ";", ":", "!", "?", ")", "]", "}"]
            // Remove stray spaces before punctuation (" ," -> ",")
            for p in punct { t = t.replacingOccurrences(of: " " + p, with: p) }
            // Balance opening brackets spacing: "( " -> "(" when it would start a line
            t = t.replacingOccurrences(of: "( ", with: "(")
            t = t.replacingOccurrences(of: "[ ", with: "[")
            t = t.replacingOccurrences(of: "{ ", with: "{")
            return t
        }
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        let normalized = normalizeInlineSpacing(s)
        let attributed = (try? AttributedString(markdown: normalized, options: options)) ?? AttributedString(normalized)
        let plain = String(attributed.characters)
        let parts = splitFragments(plain)
        var result: [AttributedString] = []
        var cursor = attributed.startIndex
        for part in parts {
            if part.isEmpty { continue }
            let end = attributed.index(cursor, offsetByCharacters: part.count)
            result.append(AttributedString(attributed[cursor..<end]))
            cursor = end
        }
        return result
    }

    var body: some View {
        // Wrap inline elements so math spans don't force a single ultra-wide line.
        // Zero spacing so inline math does not insert visual gaps between
        // adjacent text segments.
        InlineWrap(spacing: 0, lineSpacing: 0) {
            ForEach(Array(runs.enumerated()), id: \.offset) { _, token in
                switch token {
                case .text(let s):
                    if !s.isEmpty {
                        let parts = splitMarkdownFragments(s)
#if os(macOS)
                        let combined = parts.reduce(into: AttributedString()) { $0 += $1 }
                        if !combined.characters.isEmpty {
                            Text(combined)
                                .multilineTextAlignment(.leading)
                        }
#else
                        ForEach(Array(parts.enumerated()), id: \.offset) { _, frag in
                            Text(frag)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: true)
                        }
#endif
                    }
                case .inline(let latex):
                    InlineMathView(latex: latex, fontSize: fontSize)
                case .block(let latex):
                    // Should not appear here; render inline-sized just in case.
                    InlineMathView(latex: latex, fontSize: fontSize)
                case .incomplete(let raw):
                    Text(raw)
                        .foregroundStyle(Color.red)
                }
            }
        }
        // Apply base font to the container so inline Markdown keeps its
        // styles but inherits the body size/weight.
        .font(font)
    }
}

// MARK: - Inline wrapping layout
private struct InlineWrap: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 2
    // Disable pre-wrap by default so LaTeX spans do not alter where text wraps.
    // When set > 0, the layout will pre-wrap if the remaining space is below
    // this threshold.
    var minResidualWrapWidth: CGFloat = 0

    // Provide a reasonable finite fallback width when the parent offers
    // an unbounded width. This prevents pathological reflow that can occur
    // when measuring with .infinity, ensuring inline math truly stays inline
    // and the surrounding text keeps its normal wrapping behavior.
    private var fallbackWidth: CGFloat {
        #if os(visionOS)
        return 480
        #elseif os(iOS)
        // Leave comfortable margins inside chat bubbles
        return max(320, UIScreen.main.bounds.width - 64)
        #else
        return 480
        #endif
    }

    private struct LineItem {
        let index: Int
        let size: CGSize
        let baseline: CGFloat?
    }

    private struct Line {
        var items: [LineItem] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
        var baseline: CGFloat? = nil
    }

    private func measure(_ subview: LayoutSubview, width: CGFloat) -> (CGSize, CGFloat?) {
        let proposed = ProposedViewSize(width: width, height: nil)
        let size = subview.sizeThatFits(proposed)
        let dims = subview.dimensions(in: ProposedViewSize(width: size.width, height: size.height))
        let baseline = dims[VerticalAlignment.firstTextBaseline]
        let validBaseline = baseline.isFinite ? baseline : nil
        return (size, validBaseline)
    }

    private func buildLines(subviews: Subviews, maxWidth: CGFloat) -> [Line] {
        var lines: [Line] = []
        var current = Line()
        var cursorX: CGFloat = 0

        func pushLine() {
            guard !current.items.isEmpty else { return }
            let maxBaseline = current.items.compactMap { $0.baseline }.max()
            let maxDescent = current.items.compactMap { item -> CGFloat? in
                guard let base = item.baseline else { return nil }
                return item.size.height - base
            }.max()
            let maxHeight = current.items.map(\.size.height).max() ?? 0
            if let base = maxBaseline, let desc = maxDescent {
                current.baseline = base
                current.height = max(maxHeight, base + desc)
            } else {
                current.baseline = nil
                current.height = maxHeight
            }
            current.width = max(0, cursorX - spacing)
            lines.append(current)
            current = Line()
            cursorX = 0
        }

        for index in subviews.indices {
            let available = maxWidth.isFinite ? max(0, maxWidth - cursorX) : .infinity

            if minResidualWrapWidth > 0 && maxWidth.isFinite && cursorX > 0 && available < minResidualWrapWidth {
                pushLine()
            }

            var (size, baseline) = measure(subviews[index], width: max(0, maxWidth - cursorX))
            if maxWidth.isFinite && cursorX > 0 && size.width > available + 0.5 {
                pushLine()
                (size, baseline) = measure(subviews[index], width: maxWidth)
            }

            current.items.append(LineItem(index: index, size: size, baseline: baseline))
            cursorX += size.width + spacing
        }
        pushLine()
        return lines
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? fallbackWidth
        let lines = buildLines(subviews: subviews, maxWidth: maxWidth)

        var totalHeight: CGFloat = 0
        for (idx, line) in lines.enumerated() {
            totalHeight += line.height
            if idx < lines.count - 1 { totalHeight += lineSpacing }
        }
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width > 0 ? bounds.width : fallbackWidth
        let lines = buildLines(subviews: subviews, maxWidth: maxWidth)

        var cursorY = bounds.minY
        for line in lines {
            let baselineY: CGFloat = {
                if let base = line.baseline { return cursorY + base }
                return cursorY + (line.height / 2)
            }()

            var cursorX = bounds.minX
            for item in line.items {
                let y: CGFloat
                if let itemBaseline = item.baseline, let lineBaseline = line.baseline {
                    y = baselineY - itemBaseline
                } else {
                    y = cursorY + (line.height - item.size.height) / 2
                }
                subviews[item.index].place(at: CGPoint(x: cursorX, y: y),
                                           proposal: ProposedViewSize(width: item.size.width, height: item.size.height))
                cursorX += item.size.width + spacing
            }
            cursorY += line.height + lineSpacing
        }
    }
}
