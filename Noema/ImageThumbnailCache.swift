import Foundation
import SwiftUI
import ImageIO

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
private func deviceScale() -> CGFloat {
#if os(visionOS)
    // UIScreen is unavailable on visionOS; the runtime uses fixed‑scale rendering.
    return 2
#else
    return UIScreen.main.scale
#endif
}
#else
import AppKit
typealias PlatformImage = NSImage
private func deviceScale() -> CGFloat { NSScreen.main?.backingScaleFactor ?? 2 }
#endif

/// Small, synchronous thumbnail cache to avoid repeatedly decoding full-size images
/// when rendering chat attachments. Produces thumbnails capped to the view's
/// displayed size in pixels so images are never larger than their appearance.
@MainActor
final class ImageThumbnailCache {
    static let shared = ImageThumbnailCache()

    private let cache = NSCache<NSString, PlatformImage>()

    func thumbnail(for path: String, pointSize: CGSize, maxScale: CGFloat? = nil) -> PlatformImage? {
        let key = cacheKey(for: path, pointSize: pointSize, scale: maxScale ?? deviceScale())
        if let cached = cache.object(forKey: key as NSString) { return cached }

        let scale = maxScale ?? deviceScale()
        let maxPixel = Int(ceil(max(pointSize.width, pointSize.height) * scale))
        guard maxPixel > 0 else { return nil }

        let url = URL(fileURLWithPath: path)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCache: true
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }

        #if canImport(UIKit)
        let img = UIImage(cgImage: cg)
        #else
        let rep = NSBitmapImageRep(cgImage: cg)
        let img = NSImage(size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
        img.addRepresentation(rep)
        #endif

        cache.setObject(img, forKey: key as NSString)
        return img
    }

    func clear(for path: String) {
        // Clear all entries for this path regardless of size hints
        for scale in [1.0, 2.0, 3.0] as [CGFloat] {
            let sizes: [CGSize] = [CGSize(width: 80, height: 80), CGSize(width: 96, height: 96), CGSize(width: 160, height: 160), CGSize(width: 192, height: 192)]
            for sz in sizes {
                let key = cacheKey(for: path, pointSize: sz, scale: scale)
                cache.removeObject(forKey: key as NSString)
            }
        }
    }

    func clearAll() { cache.removeAllObjects() }

    private func cacheKey(for path: String, pointSize: CGSize, scale: CGFloat) -> String {
        let w = Int(pointSize.width.rounded())
        let h = Int(pointSize.height.rounded())
        let s = String(format: "%.2f", scale)
        return "\(path)#\(w)x\(h)@\(s)x"
    }
}
