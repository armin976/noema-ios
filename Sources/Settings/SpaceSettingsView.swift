#if canImport(SwiftUI)
import SwiftUI
import AutoFlow

@MainActor
final class SpaceSettingsViewModel: ObservableObject {
    @Published var profile: SpaceSettings.AutoFlowProfileSetting = .balanced
    @Published var guardNullPct: Double = 0.3
    @Published var spaceName: String = ""

    private let store: SpaceStore
    private var activeSpaceID: UUID?
    private var task: Task<Void, Never>?

    init(store: SpaceStore = .shared) {
        self.store = store
        subscribe()
    }

    deinit { task?.cancel() }

    func subscribe() {
        task = Task { [weak self] in
            guard let self else { return }
            let stream = await store.activeSpaceStream()
            for await space in stream {
                await MainActor.run {
                    self.activeSpaceID = space?.id
                    self.profile = space?.settings.autoflowProfile ?? .balanced
                    self.guardNullPct = space?.settings.guardNullPct ?? 0.3
                    self.spaceName = space?.name ?? ""
                }
            }
        }
    }

    func persistChanges() {
        guard let id = activeSpaceID else { return }
        let settings = SpaceSettings(autoflowProfile: profile, guardNullPct: guardNullPct)
        Task { try? await store.updateSettings(for: id, settings: settings) }
    }

    func pauseAutoFlowTenMinutes() {
        Task { await AutoFlowEngine.shared.pauseForTenMinutes() }
    }
}

public struct SpaceSettingsView: View {
    @StateObject private var model = SpaceSettingsViewModel()

    public init() {}

    public var body: some View {
        Section(header: Text("Space AutoFlow")) {
            Picker("AutoFlow Profile", selection: $model.profile) {
                ForEach(SpaceSettings.AutoFlowProfileSetting.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: model.profile) { _ in model.persistChanges() }

            VStack(alignment: .leading, spacing: 4) {
                Slider(value: $model.guardNullPct, in: 0...1)
                    .onChange(of: model.guardNullPct) { _ in model.persistChanges() }
                    .accessibilityLabel("Null threshold")
                Text("Clean when nulls exceed \(Int(model.guardNullPct * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Pause AutoFlow 10m") {
                model.pauseAutoFlowTenMinutes()
            }
        }
    }
}
#endif
