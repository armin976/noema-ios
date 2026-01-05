#if os(macOS)
import AppKit
import Combine

@MainActor
final class RelayControlCenter: ObservableObject {
    struct Snapshot: Equatable {
        var state: RelayManagementViewModel.ServerState
        var statusMessage: String
        var lanAddress: String?
        var currentSSID: String?
        var lastActivity: Date?
        var isLANStarting: Bool

        var isRunning: Bool {
            if case .running = state { return true }
            return false
        }

        var isStarting: Bool {
            if case .starting = state { return true }
            return false
        }
    }

    static let shared = RelayControlCenter()

    @Published private(set) var snapshot = Snapshot(state: .stopped,
                                                    statusMessage: "Relay stopped",
                                                    lanAddress: nil,
                                                    currentSSID: nil,
                                                    lastActivity: nil,
                                                    isLANStarting: false)

    private weak var delegate: RelayManagementViewModel?

    private init() {}

    func register(_ viewModel: RelayManagementViewModel) {
        delegate = viewModel
        refresh(from: viewModel)
    }

    func unregister(_ viewModel: RelayManagementViewModel) {
        guard delegate === viewModel else { return }
        delegate = nil
        snapshot = Snapshot(state: .stopped,
                            statusMessage: "Relay stopped",
                            lanAddress: nil,
                            currentSSID: nil,
                            lastActivity: nil,
                            isLANStarting: false)
    }

    func refresh(from viewModel: RelayManagementViewModel) {
        if delegate !== viewModel {
            if delegate == nil {
                delegate = viewModel
            } else {
                return
            }
        }
        snapshot = Snapshot(state: viewModel.serverState,
                            statusMessage: viewModel.statusMessage,
                            lanAddress: viewModel.lanReachableAddress,
                            currentSSID: nil,
                            lastActivity: viewModel.lastActivity,
                            isLANStarting: viewModel.isLANServerStarting)
    }

    func startRelay() {
        delegate?.start()
    }

    func stopRelay() {
        delegate?.stop()
    }

    var hasDelegate: Bool {
        delegate != nil
    }
}
#endif
