// MathViews.swift
//  MathViews.swift
//  Noema
//
//  SwiftUI bridges for SwiftMath (MTMathUILabel) with optional image caching
//  for performance. Provides inline and block math rendering with baseline
//  alignment and accessibility labels.

import SwiftUI
import SwiftMath

@MainActor struct MathRenderTuning {
    // Provide small, safe insets to avoid top/bottom glyph clipping and to
    // leave a hairline of space around inline and block math. These values are
    // intentionally conservative so line height only grows when formulas are
    // actually tall.
    static var inlineInsets: UIEdgeInsets = UIEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
    static var blockInsets: UIEdgeInsets = UIEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
}

@MainActor final class MathImageCache {
    @MainActor static let shared = MathImageCache()
    private let cache = NSCache<NSString, UIImage>()
    private init() {
        cache.countLimit = 256
        cache.totalCostLimit = 32 * 1024 * 1024
    }
    func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }
    func insert(_ image: UIImage, for key: String) {
        let cost = Int(image.size.width * image.size.height * (image.scale * image.scale))
        cache.setObject(image, forKey: key as NSString, cost: max(cost, 1))
    }
}

@MainActor func renderMathImage(latex: String, fontSize: CGFloat, display: Bool, color: UIColor, insets: UIEdgeInsets = .zero) -> UIImage? {
    // Cache key includes mode, font size, insets and color
    let insetKey = "t:\(Int(insets.top))|l:\(Int(insets.left))|b:\(Int(insets.bottom))|r:\(Int(insets.right))"
    let key = (display ? "D:" : "I:") + String(Int(fontSize)) + ":" + latex + ":" + color.description + ":" + insetKey
    if let img = MathImageCache.shared.image(for: key) { return img }
    let label = MTMathUILabel()
    label.latex = latex
    label.labelMode = display ? .display : .text
    label.fontSize = fontSize
    label.textColor = color
    label.contentInsets = insets
    // Prefer default math font
    label.font = MTFontManager().termesFont(withSize: fontSize)
    label.sizeToFit()
    let size = label.bounds.integral.size
    guard size.width > 0, size.height > 0 else { return nil }
    let format = UIGraphicsImageRendererFormat.default()
#if os(visionOS)
    format.scale = 1.0
#else
    format.scale = UIScreen.main.scale
#endif
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    let img = renderer.image { _ in
        label.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
    }
    MathImageCache.shared.insert(img, for: key)
    return img
}

struct InlineMathView: View {
    let latex: String
    var fontSize: CGFloat = UIFont.preferredFont(forTextStyle: .body).pointSize
    var useCache: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    private var uiColor: UIColor { colorScheme == .dark ? .label : .label }
    private var inlineInsets: UIEdgeInsets { MathRenderTuning.inlineInsets }

    var body: some View {
        Group {
            if useCache, let img = renderMathImage(latex: latex, fontSize: fontSize, display: false, color: uiColor, insets: inlineInsets) {
                // Render at the label's natural size (which already reflects
                // fontSize and contentInsets) so tall formulas can naturally
                // expand the line box instead of being clipped.
                let size = img.size
                Image(uiImage: img)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .frame(width: size.width, height: size.height, alignment: .leading)
                    // Approximate baseline alignment; keep a small descent tweak
                    .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.bottom] - (fontSize * 0.18) }
                    .accessibilityLabel(Text(plainAccessibilityLabel(from: latex)))
            } else {
                InlineMathUILabel(latex: latex, fontSize: fontSize, color: uiColor, insets: inlineInsets)
                    .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.bottom] - (fontSize * 0.18) }
                    .accessibilityLabel(Text(plainAccessibilityLabel(from: latex)))
            }
        }
    }
}

private struct InlineMathUILabel: UIViewRepresentable {
    let latex: String
    let fontSize: CGFloat
    let color: UIColor
    let insets: UIEdgeInsets

    func makeUIView(context: Context) -> MTMathUILabel {
        let v = MTMathUILabel()
        v.labelMode = .text
        v.textAlignment = .left
        v.fontSize = fontSize
        v.textColor = color
        v.contentInsets = insets
        v.font = MTFontManager().termesFont(withSize: fontSize)
        // Ensure the label reports its intrinsic width so it stays inline
        // instead of expanding to fill the row and forcing a line break.
        v.setContentHuggingPriority(.required, for: .horizontal)
        v.setContentHuggingPriority(.required, for: .vertical)
        v.setContentCompressionResistancePriority(.required, for: .horizontal)
        v.setContentCompressionResistancePriority(.required, for: .vertical)
        v.latex = latex
        return v
    }
    func updateUIView(_ uiView: MTMathUILabel, context: Context) {
        uiView.fontSize = fontSize
        uiView.textColor = color
        uiView.contentInsets = insets
        uiView.latex = latex
    }
}

struct BlockMathView: View {
    let latex: String
    var fontSize: CGFloat = UIFont.preferredFont(forTextStyle: .title3).pointSize
    var useCache: Bool = true
    @Environment(\.colorScheme) private var colorScheme
    private var uiColor: UIColor { colorScheme == .dark ? .label : .label }
    private var blockInsets: UIEdgeInsets { MathRenderTuning.blockInsets }

    // Added helper to compute display size preserving intrinsic aspect ratio without expanding to full width.
    private func displaySize(for image: UIImage) -> CGSize {
        let height = fontSize * 1.2 // slightly larger than surrounding text for display math
        guard image.size.height > 0 else { return CGSize(width: height, height: height) }
        let aspect = image.size.width / image.size.height
        return CGSize(width: height * aspect, height: height)
    }

    var body: some View {
        Group {
            if useCache, let img = renderMathImage(latex: latex, fontSize: fontSize, display: true, color: uiColor, insets: blockInsets) {
                let size = displaySize(for: img)
                Image(uiImage: img)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .frame(width: size.width, height: size.height, alignment: .leading)
                    .accessibilityLabel(Text(plainAccessibilityLabel(from: latex)))
            } else {
                BlockMathUILabel(latex: latex, fontSize: fontSize, color: uiColor, insets: blockInsets)
                    .accessibilityLabel(Text(plainAccessibilityLabel(from: latex)))
            }
        }
        // Align leading without forcing full-width occupation and avoid extra vertical padding
        .frame(maxWidth: .infinity, alignment: .leading)
        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.top] }
        .padding(.vertical, 0)
    }
}

private func plainAccessibilityLabel(from latex: String) -> String {
    // Simple fallback: strip common TeX control chars for a readable label
    var s = latex
    let patterns: [String] = ["\\\\", "\\[", "\\]", "\\(", "\\)", "{", "}", "$", "^", "_", "\\\nfrac", "\\sum", "\\int", "\\cdot"]
    for p in patterns { s = s.replacingOccurrences(of: p, with: " ") }
    s = s.replacingOccurrences(of: "  ", with: " ")
    return s.trimmingCharacters(in: .whitespacesAndNewlines)
}

private struct BlockMathUILabel: UIViewRepresentable {
    let latex: String
    let fontSize: CGFloat
    let color: UIColor
    let insets: UIEdgeInsets

    func makeUIView(context: Context) -> MTMathUILabel {
        let v = MTMathUILabel()
        v.labelMode = .display
        v.textAlignment = .left
        v.fontSize = fontSize
        v.textColor = color
        v.contentInsets = insets
        v.font = MTFontManager().termesFont(withSize: fontSize)
        v.latex = latex
        return v
    }
    func updateUIView(_ uiView: MTMathUILabel, context: Context) {
        uiView.fontSize = fontSize
        uiView.textColor = color
        uiView.contentInsets = insets
        uiView.latex = latex
    }
}

