#if canImport(SwiftUI)
import SwiftUI

@MainActor
final class SpacesSidebarViewModel: ObservableObject {
    @Published var spaces: [Space] = []
    @Published var selection: Space.ID?
    @Published var isPresentingNewSpace = false
    @Published var isPresentingRename = false
    @Published var draftName: String = ""

    private var renameTarget: Space?
    private let store: SpaceStore
    private var spacesTask: Task<Void, Never>?
    private var activeTask: Task<Void, Never>?

    init(store: SpaceStore = .shared) {
        self.store = store
        subscribe()
    }

    deinit {
        spacesTask?.cancel()
        activeTask?.cancel()
    }

    func subscribe() {
        spacesTask = Task { [weak self] in
            guard let self else { return }
            let stream = await store.spacesStream()
            for await spaces in stream {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.spaces = spaces
                    }
                }
            }
        }

        activeTask = Task { [weak self] in
            guard let self else { return }
            let stream = await store.activeSpaceStream()
            for await active in stream {
                await MainActor.run {
                    self.selection = active?.id
                }
            }
        }
    }

    func select(_ id: Space.ID?) {
        guard selection != id else { return }
        selection = id
        guard let id else { return }
        Task { try? await store.switchTo(id) }
    }

    func createSpace() {
        draftName = suggestedName()
        isPresentingNewSpace = true
    }

    func confirmCreate() {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Task {
            let space = try await store.create(name: name)
            await MainActor.run {
                self.selection = space.id
            }
        }
        isPresentingNewSpace = false
    }

    func beginRename(_ space: Space) {
        renameTarget = space
        draftName = space.name
        isPresentingRename = true
    }

    func confirmRename() {
        guard let renameTarget else { return }
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Task { try? await store.rename(id: renameTarget.id, name: name) }
        isPresentingRename = false
    }

    private func suggestedName() -> String {
        let base = "New Space"
        if !spaces.contains(where: { $0.name == base }) { return base }
        var index = 2
        while spaces.contains(where: { $0.name == "\(base) \(index)" }) {
            index += 1
        }
        return "\(base) \(index)"
    }
}

public struct SpacesSidebar<Content: View>: View {
    @StateObject private var model = SpacesSidebarViewModel()
    private let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { model.selection }, set: { model.select($0) })) {
                Section("Spaces") {
                    ForEach(model.spaces) { space in
                        HStack {
                            Text(space.name)
                                .font(.body)
                                .accessibilityLabel(Text("Space \(space.name)"))
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .tag(space.id)
                        .onTapGesture { model.select(space.id) }
                        .contextMenu {
                            Button("Rename") { model.beginRename(space) }
                        }
                    }
                    if model.spaces.isEmpty {
                        Text("No spaces yet")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        model.createSpace()
                    } label: {
                        Label("Create Space", systemImage: "plus")
                    }
                    .accessibilityLabel("Create a new space")
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Spaces")
            .toolbar { toolbarContent }
        } detail: {
            content()
        }
        .sheet(isPresented: $model.isPresentingNewSpace) {
            nameSheet(title: "Create Space", confirmTitle: "Create") {
                model.confirmCreate()
            }
        }
        .sheet(isPresented: $model.isPresentingRename) {
            nameSheet(title: "Rename Space", confirmTitle: "Save") {
                model.confirmRename()
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                model.createSpace()
            } label: {
                Label("New Space", systemImage: "plus")
            }
            .accessibilityLabel("Create Space")
        }
    }

    @ViewBuilder
    private func nameSheet(title: String, confirmTitle: String, action: @escaping () -> Void) -> some View {
        NavigationStack {
            Form {
                TextField("Name", text: $model.draftName)
                    .textInputAutocapitalization(.words)
                    .accessibilityLabel("Space name")
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        model.isPresentingNewSpace = false
                        model.isPresentingRename = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmTitle) { action() }
                        .disabled(model.draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
#endif
