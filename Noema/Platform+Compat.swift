import SwiftUI

#if os(macOS)
import AppKit

typealias UIColor = NSColor
typealias UIImage = NSImage
typealias UIFont = NSFont
typealias UIEdgeInsets = NSEdgeInsets

extension NSColor {
    static var label: NSColor { .labelColor }
    static var systemBackground: NSColor { .windowBackgroundColor }
    static var systemGray6: NSColor { .controlBackgroundColor }
    static var systemGray5: NSColor { .controlBackgroundColor.blended(withFraction: 0.15, of: .textBackgroundColor) ?? .controlBackgroundColor }
    static var systemGray4: NSColor { .separatorColor }
    static var systemGray3: NSColor { .separatorColor.withAlphaComponent(0.6) }
    static var secondarySystemBackground: NSColor { .underPageBackgroundColor }
    static var secondarySystemGroupedBackground: NSColor { .controlBackgroundColor }
}

extension NSEdgeInsets {
    static let zero = NSEdgeInsets()
}

extension NSImage {
    var scale: CGFloat {
        if let rep = bestRepresentation(for: NSRect(origin: .zero, size: size), context: nil, hints: nil) {
            let width = CGFloat(rep.pixelsWide)
            return size.width > 0 ? max(width / size.width, NSScreen.main?.backingScaleFactor ?? 1) : 1
        }
        return NSScreen.main?.backingScaleFactor ?? 1
    }

    func jpegData(compressionQuality: CGFloat) -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        let properties: [NSBitmapImageRep.PropertyKey: Any] = [
            .compressionFactor: compressionQuality
        ]
        return bitmap.representation(using: .jpeg, properties: properties)
    }
}

extension NSImage {
    /// Downscale image to fit within `targetSize` preserving aspect ratio.
    /// Returns `self` if already smaller than target.
    func resizedDown(to targetSize: CGSize) -> NSImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(targetSize.width / size.width, targetSize.height / size.height)
        if scale >= 1 { return self }
        let newSize = NSSize(width: floor(size.width * scale), height: floor(size.height * scale))
        let out = NSImage(size: newSize)
        out.lockFocus()
        defer { out.unlockFocus() }
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: size), operation: .copy, fraction: 1.0)
        return out
    }
}

extension Image {
    init(platformImage: NSImage) {
        self.init(nsImage: platformImage)
    }
}

extension Color {
    init(uiColor: NSColor) {
        self.init(nsColor: uiColor)
    }
}

func preferredFontSize(_ style: NSFont.TextStyle) -> CGFloat {
    NSFont.preferredFont(forTextStyle: style).pointSize
}

#else
import UIKit

typealias UIColor = UIKit.UIColor
typealias UIImage = UIKit.UIImage
typealias UIFont = UIKit.UIFont
typealias UIEdgeInsets = UIKit.UIEdgeInsets

extension Image {
    init(platformImage: UIImage) {
        self.init(uiImage: platformImage)
    }
}

func preferredFontSize(_ style: UIFont.TextStyle) -> CGFloat {
    UIFont.preferredFont(forTextStyle: style).pointSize
}

#endif

enum PlatformAutocapitalizationStyle {
    case words
    case never
}

enum PlatformKeyboardType {
    case numberPad
    case url
}

extension View {
    @ViewBuilder
    func platformAutocapitalization(_ style: PlatformAutocapitalizationStyle) -> some View {
        #if canImport(UIKit)
        switch style {
        case .words:
            textInputAutocapitalization(.words)
        case .never:
            textInputAutocapitalization(.never)
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    func platformKeyboardType(_ type: PlatformKeyboardType) -> some View {
        #if canImport(UIKit)
        switch type {
        case .numberPad:
            keyboardType(.numberPad)
        case .url:
            keyboardType(.URL)
        }
        #else
        self
        #endif
    }
}
