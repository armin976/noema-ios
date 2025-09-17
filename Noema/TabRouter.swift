// TabRouter.swift
import SwiftUI

@MainActor
enum MainTab: Hashable {
    case chat, stored, explore, settings
}

@MainActor
final class TabRouter: ObservableObject {
    @Published var selection: MainTab = .chat
}

