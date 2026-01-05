// TabRouter.swift
import SwiftUI

@MainActor
enum MainTab: Hashable {
    case chat
    case stored
    case explore
#if os(macOS)
    case relay
#endif
    case settings
}

@MainActor
final class TabRouter: ObservableObject {
    @Published var selection: MainTab = .chat
}

