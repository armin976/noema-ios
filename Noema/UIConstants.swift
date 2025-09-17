// UIConstants.swift
import SwiftUI

@MainActor
struct UIConstants {
    // Feature flag to show/hide multimodal UI (images, vision badges, type picker)
    static let showMultimodalUI: Bool = false

    static var cornerRadius: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 16 : 12
    }
    
    static var smallCornerRadius: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 12 : 8
    }
    
    static var largeCornerRadius: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 20 : 15
    }
    
    static var extraLargeCornerRadius: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 24 : 18
    }
    
    static var defaultPadding: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 20 : 16
    }
    
    static var compactPadding: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 12 : 8
    }
    
    static var widePadding: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 32 : 20
    }
}

extension View {
    func adaptiveCornerRadius(_ size: AdaptiveCornerSize = .medium) -> some View {
        self.clipShape(RoundedRectangle(cornerRadius: size.value))
    }
}

@MainActor
enum AdaptiveCornerSize {
    case small
    case medium
    case large
    case extraLarge
    
    var value: CGFloat {
        switch self {
        case .small:
            return UIConstants.smallCornerRadius
        case .medium:
            return UIConstants.cornerRadius
        case .large:
            return UIConstants.largeCornerRadius
        case .extraLarge:
            return UIConstants.extraLargeCornerRadius
        }
    }
}