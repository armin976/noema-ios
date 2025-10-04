// MathRichText.swift
//  MathRichText.swift
//  Noema
//
//  Renders mixed text with inline and block LaTeX using MathTokenizer and
//  SwiftMath-backed views. Keeps baseline alignment for inline math and flows
//  across lines.

import SwiftUI

struct MathRichText: View {
    let source: String
    var bodyFont: Font = .body

    var body: some View {
        RichMathTextLabel(source: source, bodyFont: bodyFont)
    }
}

private struct RichMathTextLabel: View {
    let source: String
    var bodyFont: Font

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
                        if !inlinePara.isEmpty { currentInline.append(.text(inlinePara)) }
                        if idx < paragraphs.count - 1 { flushInline() }
                    }
                }
            }
            flushInline()
            return out
        }()

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                switch seg {
                case .inline(let inlineTokens):
                    InlineLine(tokens: inlineTokens, bodyFont: bodyFont)
                case .block(let latex):
                    BlockMathView(latex: latex)
                case .incomplete(let raw):
                    Text(raw)
                        .foregroundStyle(Color.red)
                }
            }
        }
    }
}

private struct InlineLine: View {
    let tokens: [MathToken]
    var bodyFont: Font
    @ScaledMetric(relativeTo: .body) private var inlineSize: CGFloat = UIFont.preferredFont(forTextStyle: .body).pointSize

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
                        ForEach(Array(parts.enumerated()), id: \.offset) { _, frag in
                            Text(frag)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: true)
                        }
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

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? fallbackWidth
        var cursorX: CGFloat = 0
        var totalHeight: CGFloat = 0
        var lineHeight: CGFloat = 0

        func measure(_ i: Int, width: CGFloat) -> CGSize {
            subviews[i].sizeThatFits(ProposedViewSize(width: width, height: nil))
        }

        for i in subviews.indices {
            let available = maxWidth.isFinite ? max(0, maxWidth - cursorX) : .infinity

            // If the remaining space is too small to render readable text,
            // wrap before measuring this element so it gets full line width.
            if minResidualWrapWidth > 0 && maxWidth.isFinite && cursorX > 0 && available < minResidualWrapWidth {
                cursorX = 0
                totalHeight += lineHeight + lineSpacing
                lineHeight = 0
            }

            var size = measure(i, width: max(0, maxWidth - cursorX))
            if maxWidth.isFinite && cursorX > 0 && size.width > available + 0.5 {
                // wrap
                cursorX = 0
                totalHeight += lineHeight + lineSpacing
                lineHeight = 0
                size = measure(i, width: maxWidth)
            }
            cursorX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        let finalHeight = totalHeight + lineHeight
        let finalWidth = maxWidth
        return CGSize(width: finalWidth, height: finalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width > 0 ? bounds.width : fallbackWidth
        var cursorX: CGFloat = 0
        var cursorY: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        func measure(_ i: Int, width: CGFloat) -> CGSize {
            subviews[i].sizeThatFits(ProposedViewSize(width: width, height: nil))
        }

        for i in subviews.indices {
            let available = max(0, maxWidth - cursorX)

            // Pre-wrap if the remaining space is too small for readable text
            if minResidualWrapWidth > 0 && cursorX > 0 && available < minResidualWrapWidth {
                cursorX = 0
                cursorY += lineHeight + lineSpacing
                lineHeight = 0
            }

            var size = measure(i, width: max(0, maxWidth - cursorX))
            if cursorX > 0 && size.width > available + 0.5 {
                // wrap
                cursorX = 0
                cursorY += lineHeight + lineSpacing
                lineHeight = 0
                size = measure(i, width: maxWidth)
            }
            let origin = CGPoint(x: bounds.minX + cursorX, y: cursorY)
            subviews[i].place(at: origin, proposal: ProposedViewSize(width: size.width, height: size.height))
            cursorX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

