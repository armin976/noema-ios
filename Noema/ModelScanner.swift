// ModelScanner.swift
import Foundation

enum ModelScanner {
    static func layerCount(for url: URL, format: ModelFormat) -> Int {
        switch format {
        case .gguf:
            let cCount = Int(gguf_layer_count(url.path))
            if cCount > 0 { return cCount }
            return GGUFMetadata.layerCount(at: url) ?? 0
        case .mlx, .slm:
            return 0
        case .apple:
            return 0
        }
    }
}
