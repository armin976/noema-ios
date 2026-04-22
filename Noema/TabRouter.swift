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
    @Published var pendingStoredDatasetID: String?
    @Published var isAFMHiddenNoticeVisible = false

    private var afmHiddenNoticeTask: Task<Void, Never>?

    func showAFMHiddenNotice(duration: TimeInterval = 3) {
        afmHiddenNoticeTask?.cancel()
        isAFMHiddenNoticeVisible = true
        afmHiddenNoticeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.isAFMHiddenNoticeVisible = false
            self?.afmHiddenNoticeTask = nil
        }
    }

    func dismissAFMHiddenNotice() {
        afmHiddenNoticeTask?.cancel()
        afmHiddenNoticeTask = nil
        isAFMHiddenNoticeVisible = false
    }
}
