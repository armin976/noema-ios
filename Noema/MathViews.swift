// MathViews.swift
//  MathViews.swift
//  Noema
//
//  SwiftUI bridges for SwiftMath (MTMathUILabel) with optional image caching
//  for performance. Provides inline and block math rendering with baseline
//  alignment and accessibility labels.

import SwiftUI
import SwiftMath
#if os(macOS)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

@MainActor struct MathRenderTuning {
    // Provide small, safe insets to avoid top/bottom glyph clipping and to
    // leave a hairline of space around inline and block math. These values are
    // intentionally conservative so line height only grows when formulas are
    // actually tall.
    static var inlineInsets: UIEdgeInsets = UIEdgeInsets(top: 3, left: 0, bottom: 3, right: 0)
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

@MainActor
private func resolvedMathColor(for colorScheme: ColorScheme) -> UIColor {
#if os(macOS)
    // Prefer explicit static colors so caching stays deterministic per scheme.
    return colorScheme == .dark ? UIColor.white : UIColor.label
#else
    let style: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
    let trait = UITraitCollection(userInterfaceStyle: style)
    return UIColor.label.resolvedColor(with: trait)
#endif
}

private func colorSignature(for color: UIColor) -> String {
#if os(macOS)
    let converted = color.usingColorSpace(.sRGB) ?? color
    let components = converted.cgColor.components ?? []
#else
    let srgb = CGColorSpace(name: CGColorSpace.sRGB)
    let converted = color.cgColor.converted(to: srgb ?? color.cgColor.colorSpace ?? CGColorSpaceCreateDeviceRGB(), intent: .relativeColorimetric, options: nil) ?? color.cgColor
    let components = converted.components ?? []
#endif
    let rounded = components.map { String(format: "%.4f", Double($0)) }.joined(separator: "|")
#if os(macOS)
    let spaceName = converted.cgColor.colorSpace?.name as String? ?? "cs"
#else
    let spaceName = converted.colorSpace?.name as String? ?? "cs"
#endif
    return "\(spaceName)|\(rounded)"
}

@MainActor func renderMathImage(latex: String, fontSize: CGFloat, isDisplayMode: Bool, color: UIColor, insets: UIEdgeInsets = .zero) -> UIImage? {
    // Cache key includes mode, font size, insets and a resolved color signature so
    // light/dark appearance swaps never reuse stale glyph images.
    let insetKey = "t:\(Int(insets.top))|l:\(Int(insets.left))|b:\(Int(insets.bottom))|r:\(Int(insets.right))"
    let colorKey = colorSignature(for: color)
    let key = "\(isDisplayMode ? "D" : "I"):\(Int(fontSize)):\(colorKey):\(insetKey):\(latex)"
    if let img = MathImageCache.shared.image(for: key) { return img }
    let label = MTMathUILabel()
    label.latex = latex
    label.labelMode = isDisplayMode ? MTMathUILabelMode.display : MTMathUILabelMode.text
    label.fontSize = fontSize
    label.textColor = color
    label.contentInsets = insets
    // Prefer default math font
    label.font = MTFontManager().termesFont(withSize: fontSize)
    let fittingSize = label.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
    let size = CGSize(width: ceil(fittingSize.width), height: ceil(fittingSize.height))
    label.frame = CGRect(origin: .zero, size: size)
#if !os(macOS)
    label.layoutIfNeeded()
#endif
    guard size.width > 0, size.height > 0 else { return nil }

#if os(macOS)
    let view = MTMathUILabel(frame: CGRect(origin: .zero, size: size))
    view.latex = latex
    view.labelMode = isDisplayMode ? MTMathUILabelMode.display : MTMathUILabelMode.text
    view.fontSize = fontSize
    view.textColor = color
    view.contentInsets = insets
    view.font = MTFontManager().termesFont(withSize: fontSize)
    view.layoutSubtreeIfNeeded()
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
    view.cacheDisplay(in: view.bounds, to: rep)
    let image = NSImage(size: size)
    image.addRepresentation(rep)
    MathImageCache.shared.insert(image, for: key)
    return image
#else
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
#endif
}

struct InlineMathView: View {
    let latex: String
    var fontSize: CGFloat = preferredFontSize(.body)
    var useCache: Bool = true

    @Environment(\.colorScheme) private var colorScheme
    private var uiColor: UIColor { resolvedMathColor(for: colorScheme) }
    private var inlineInsets: UIEdgeInsets { MathRenderTuning.inlineInsets }

    var body: some View {
        Group {
            if useCache, let img = renderMathImage(latex: latex, fontSize: fontSize, isDisplayMode: false, color: uiColor, insets: inlineInsets) {
                // Render at the label's natural size (which already reflects
                // fontSize and contentInsets) so tall formulas can naturally
                // expand the line box instead of being clipped.
                let size = img.size
                Image(platformImage: img)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .renderingMode(.original)
                    .frame(width: size.width, height: size.height, alignment: .leading)
                    // Approximate baseline alignment; keep a small descent tweak
                    .alignmentGuide(.firstTextBaseline) { d in
                        d[VerticalAlignment.bottom] - (inlineInsets.bottom + fontSize * 0.22)
                    }
                    .accessibilityLabel(Text(plainAccessibilityLabel(from: latex)))
            } else {
                InlineMathUILabel(latex: latex, fontSize: fontSize, color: uiColor, insets: inlineInsets)
                    .alignmentGuide(.firstTextBaseline) { d in
                        d[VerticalAlignment.bottom] - (inlineInsets.bottom + fontSize * 0.22)
                    }
                    .accessibilityLabel(Text(plainAccessibilityLabel(from: latex)))
            }
        }
    }
}

#if os(macOS)
private struct InlineMathUILabel: NSViewRepresentable {
    let latex: String
    let fontSize: CGFloat
    let color: UIColor
    let insets: UIEdgeInsets

    func makeNSView(context: Context) -> MTMathUILabel {
        let v = MTMathUILabel()
        v.labelMode = .text
        v.textAlignment = .left
        v.fontSize = fontSize
        v.textColor = color
        v.contentInsets = insets
        v.font = MTFontManager().termesFont(withSize: fontSize)
        v.latex = latex
        return v
    }

    func updateNSView(_ nsView: MTMathUILabel, context: Context) {
        nsView.fontSize = fontSize
        nsView.textColor = color
        nsView.contentInsets = insets
        nsView.latex = latex
    }
}
#else
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
#endif

struct BlockMathView: View {
    let latex: String
    var fontSize: CGFloat = preferredFontSize(.title3)
    var useCache: Bool = true
    @Environment(\.colorScheme) private var colorScheme
    private var uiColor: UIColor { resolvedMathColor(for: colorScheme) }
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
            if useCache, let img = renderMathImage(latex: latex, fontSize: fontSize, isDisplayMode: true, color: uiColor, insets: blockInsets) {
                let size = displaySize(for: img)
                Image(platformImage: img)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .renderingMode(.original)
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

#if os(macOS)
private struct BlockMathUILabel: NSViewRepresentable {
    let latex: String
    let fontSize: CGFloat
    let color: UIColor
    let insets: UIEdgeInsets

    func makeNSView(context: Context) -> MTMathUILabel {
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
    func updateNSView(_ nsView: MTMathUILabel, context: Context) {
        nsView.fontSize = fontSize
        nsView.textColor = color
        nsView.contentInsets = insets
        nsView.latex = latex
    }
}
#else
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
#endif
