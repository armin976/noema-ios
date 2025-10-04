#if os(visionOS)
import SwiftUI
import RealityKit
import UIKit
import simd

// Allow conditional availability within SceneBuilder closures (e.g., if #available).
extension SceneBuilder {
    static func buildLimitedAvailability<Content>(_ component: Content) -> Content where Content: SwiftUI.Scene {
        component
    }
}

enum VisionWindowMode {
    case planar
    case volumetric
}

enum VisionSceneID {
    static let planarWindow = "com.noema.vision.planar"
    static let storedPanelWindow = "com.noema.vision.stored"
}

private struct VisionPinnedNote: Identifiable, Hashable {
    let id: UUID
    let text: String
    let createdAt: Date

    init(id: UUID = UUID(), text: String, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}

struct NoemaVisionMainScene: SwiftUI.Scene {
    @StateObject private var tabRouter = TabRouter()
    @StateObject private var chatVM = ChatVM()
    @StateObject private var modelManager = AppModelManager()
    @StateObject private var datasetManager = DatasetManager()
    @StateObject private var downloadController = DownloadController()
    @StateObject private var walkthroughManager = GuidedWalkthroughManager()
    @State private var immersiveSpaceActive = false
    @State private var pinnedNotes: [VisionPinnedNote] = []
    @AppStorage("appearance") private var appearance = "system"

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private func storedPanelView() -> some View {
        StoredPanelWindow()
            .environmentObject(tabRouter)
            .environmentObject(chatVM)
            .environmentObject(modelManager)
            .environmentObject(datasetManager)
            .environmentObject(downloadController)
            .environmentObject(walkthroughManager)
            .preferredColorScheme(colorScheme)
    }

    @SceneBuilder
    var body: some SwiftUI.Scene {
        WindowGroup(id: VisionSceneID.planarWindow) {
            VisionMainContainer(
                mode: .planar,
                tabRouter: tabRouter,
                chatVM: chatVM,
                modelManager: modelManager,
                datasetManager: datasetManager,
                downloadController: downloadController,
                walkthroughManager: walkthroughManager,
                immersiveSpaceActive: $immersiveSpaceActive,
                pinnedNotes: $pinnedNotes
            )
            .preferredColorScheme(colorScheme)
        }
        .defaultSize(width: 1100, height: 840)

        storedPanelScene

        ImmersiveSpace(id: VisionImmersiveView.spaceID) {
            VisionImmersiveView(isActive: $immersiveSpaceActive, pinnedNotes: $pinnedNotes)
                .environmentObject(chatVM)
                .environmentObject(modelManager)
        }
    }

    private var storedPanelScene: some SwiftUI.Scene {
        WindowGroup(id: VisionSceneID.storedPanelWindow) {
            storedPanelView()
        }
        .defaultSize(width: 420, height: 560)
        .windowResizability(.contentSize)
        .windowStyle(.plain)
    }
}

private struct VisionMainContainer: View {
    let mode: VisionWindowMode
    let tabRouter: TabRouter
    @ObservedObject var chatVM: ChatVM
    @ObservedObject var modelManager: AppModelManager
    @ObservedObject var datasetManager: DatasetManager
    @ObservedObject var downloadController: DownloadController
    @ObservedObject var walkthroughManager: GuidedWalkthroughManager
    @Binding var immersiveSpaceActive: Bool
    @Binding var pinnedNotes: [VisionPinnedNote]
    @State private var immersiveError: String?
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        Group {
            switch mode {
            case .planar, .volumetric:
                planarView
            }
        }
        .alert("Immersive Space", isPresented: Binding(get: { immersiveError != nil }, set: { _ in immersiveError = nil })) {
            Button("OK", role: .cancel) { immersiveError = nil }
        } message: {
            Text(immersiveError ?? "")
        }
    }

    private var baseContent: some View {
        ContentView(
            mode: mode,
            tabRouter: tabRouter,
            chatVM: chatVM,
            modelManager: modelManager,
            datasetManager: datasetManager,
            downloadController: downloadController,
            walkthroughManager: walkthroughManager
        )
    }

    @ViewBuilder
    private var planarView: some View {
        baseContent
    }

}

private struct VisionImmersiveView: View {
    static let spaceID = "NoemaImmersiveSpace"

    @EnvironmentObject private var chatVM: ChatVM
    @EnvironmentObject private var modelManager: AppModelManager
    @Binding var isActive: Bool
    @Binding var pinnedNotes: [VisionPinnedNote]
    @State private var scene = VisionImmersiveScene()

    var body: some View {
        RealityView { content in
            content.add(scene.root)
        } update: { _ in
            scene.updateOutput(text: assistantSummary)
            scene.updateShelf(with: modelManager.downloadedModels)
            scene.updateStatus(isStreaming: chatVM.isStreaming, rate: chatVM.msgs.last?.perf?.avgTokPerSec)
            scene.updatePinnedNotes(pinnedNotes)
        }
        .onChange(of: modelManager.downloadedModels) { models in
            scene.updateShelf(with: models)
        }
        .onChange(of: pinnedNotes) { notes in
            scene.updatePinnedNotes(notes)
        }
        .onAppear { isActive = true }
        .onDisappear { isActive = false }
    }

    private var assistantSummary: String {
        if let streaming = chatVM.msgs.last, streaming.streaming {
            return streaming.text.isEmpty ? "Generating response…" : streaming.text
        }
        if let message = chatVM.msgs.reversed().first(where: { $0.role != "🧑‍💻" && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return message.text
        }
        return chatVM.prompt.isEmpty ? "No assistant output yet." : "Awaiting response…"
    }
}

@MainActor
private final class VisionImmersiveScene {
    let root: AnchorEntity
    private let panel: ModelEntity
    private let textEntity: ModelEntity
    private let shelfParent: Entity
    private let statusOrb: ModelEntity
    private let pinnedParent: Entity
    private var currentOutput: String = ""
    private var statusColor: UIColor = .systemTeal
    private var shelfEntities: [String: Entity] = [:]
    private var pinnedEntities: [UUID: Entity] = [:]

    init() {
        let anchor = AnchorEntity()
        anchor.position = [0, 1.35, -1.4]
        root = anchor

        let panelMaterial = SimpleMaterial(color: UIColor(white: 1.0, alpha: 0.28), roughness: 0.2, isMetallic: false)
        panel = ModelEntity(mesh: .generatePlane(width: 0.9, height: 0.5, cornerRadius: 0.05), materials: [panelMaterial])
        panel.position = [0, 0.3, 0]
        panel.orientation = simd_quatf(angle: -0.12, axis: [1, 0, 0])
        panel.generateCollisionShapes(recursive: true)
        panel.components.set(InputTargetComponent())
        anchor.addChild(panel)

        textEntity = ModelEntity(mesh: Self.makeTextMesh("Welcome to Noema on visionOS."), materials: [SimpleMaterial(color: .white, roughness: 0.15, isMetallic: false)])
        textEntity.position = [0, 0.02, 0.02]
        textEntity.scale = [0.0024, 0.0024, 0.0024]
        panel.addChild(textEntity)

        shelfParent = Entity()
        shelfParent.position = [0, -0.28, 0.05]
        panel.addChild(shelfParent)

        statusOrb = ModelEntity(mesh: .generateSphere(radius: 0.055), materials: [SimpleMaterial(color: statusColor.withAlphaComponent(0.85), roughness: 0.1, isMetallic: false)])
        statusOrb.position = [0.36, 0.33, 0.05]
        statusOrb.generateCollisionShapes(recursive: true)
        statusOrb.components.set(InputTargetComponent())
        panel.addChild(statusOrb)

        pinnedParent = Entity()
        pinnedParent.position = [-0.55, 0.1, 0.02]
        panel.addChild(pinnedParent)
    }

    func updateOutput(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.isEmpty ? "No assistant output yet." : trimmed
        guard normalized != currentOutput else { return }
        currentOutput = normalized
        let mesh = Self.makeTextMesh(normalized)
        textEntity.model = ModelComponent(mesh: mesh, materials: [SimpleMaterial(color: .white, roughness: 0.1, isMetallic: false)])
    }

    func updateShelf(with models: [LocalModel]) {
        let top = Array(models.prefix(5))
        var seen = Set<String>()
        for (index, model) in top.enumerated() {
            let id = model.id
            let entity: Entity
            if let existing = shelfEntities[id] {
                entity = existing
            } else {
                entity = makeShelfEntity(for: model)
                shelfParent.addChild(entity)
                shelfEntities[id] = entity
            }
            let spacing: Float = 0.22
            let originOffset = Float(top.count - 1) * spacing / 2
            entity.position = [Float(index) * spacing - originOffset, 0, 0]
            seen.insert(id)
        }
        for (id, entity) in shelfEntities where !seen.contains(id) {
            entity.removeFromParent()
            shelfEntities.removeValue(forKey: id)
        }
    }

    func updateStatus(isStreaming: Bool, rate: Double?) {
        let desired = isStreaming ? UIColor.systemGreen : UIColor.systemTeal
        if desired != statusColor {
            statusColor = desired
            statusOrb.model = ModelComponent(mesh: .generateSphere(radius: 0.055), materials: [SimpleMaterial(color: desired.withAlphaComponent(0.85), roughness: 0.1, isMetallic: false)])
        }
        let pulse = isStreaming ? (1.0 + 0.12 * sin(Float(Date().timeIntervalSinceReferenceDate) * 3.2)) : 1.0
        statusOrb.scale = [pulse, pulse, pulse]
        if let rate, isStreaming == false {
            let summary = String(format: "%.1f tok/s", rate)
            let label = ModelEntity(mesh: Self.makeTextMesh(summary), materials: [SimpleMaterial(color: .white, roughness: 0.1, isMetallic: false)])
            label.position = [0, -0.12, 0]
            label.scale = [0.0016, 0.0016, 0.0016]
            if statusOrb.children.isEmpty {
                statusOrb.addChild(label)
            } else {
                statusOrb.children[0].removeFromParent()
                statusOrb.addChild(label)
            }
        } else if !statusOrb.children.isEmpty && isStreaming {
            statusOrb.children.removeAll()
        }
    }

    func updatePinnedNotes(_ notes: [VisionPinnedNote]) {
        var seen = Set<UUID>()
        for (index, note) in notes.enumerated() {
            let entity: Entity
            if let existing = pinnedEntities[note.id] {
                entity = existing
                updatePinnedText(for: entity, text: note.text)
            } else {
                entity = makePinnedEntity(for: note)
                pinnedParent.addChild(entity)
                pinnedEntities[note.id] = entity
            }
            entity.position = [0, Float(index) * 0.18, 0]
            seen.insert(note.id)
        }
        for (id, entity) in pinnedEntities where !seen.contains(id) {
            entity.removeFromParent()
            pinnedEntities.removeValue(forKey: id)
        }
    }

    private static func makeTextMesh(_ text: String) -> MeshResource {
        let font = MeshResource.Font.systemFont(ofSize: 0.08, weight: .regular)
        let frame = CGRect(x: -0.42, y: -0.22, width: 0.84, height: 0.44)
        return MeshResource.generateText(text, extrusionDepth: 0.001, font: font, containerFrame: frame, alignment: .left, lineBreakMode: .byWordWrapping)
    }

    private func makeShelfEntity(for model: LocalModel) -> Entity {
        let baseColor: UIColor
        switch model.format {
        case .gguf: baseColor = UIColor(red: 0.28, green: 0.44, blue: 0.88, alpha: 0.85)
        case .mlx: baseColor = UIColor(red: 0.95, green: 0.53, blue: 0.2, alpha: 0.85)
        case .slm: baseColor = UIColor(red: 0.16, green: 0.73, blue: 0.86, alpha: 0.85)
        case .apple: baseColor = UIColor(red: 0.33, green: 0.78, blue: 0.45, alpha: 0.85)
        }
        let body = ModelEntity(mesh: .generateBox(width: 0.18, height: 0.07, depth: 0.04, cornerRadius: 0.02), materials: [SimpleMaterial(color: baseColor, roughness: 0.25, isMetallic: false)])
        body.position = [0, 0, 0]
        body.generateCollisionShapes(recursive: true)
        body.components.set(InputTargetComponent())

        let labelMesh = MeshResource.generateText(model.name, extrusionDepth: 0.001, font: .systemFont(ofSize: 0.06, weight: .medium), containerFrame: CGRect(x: -0.08, y: -0.025, width: 0.16, height: 0.05), alignment: .center, lineBreakMode: .byTruncatingTail)
        let label = ModelEntity(mesh: labelMesh, materials: [SimpleMaterial(color: .white, roughness: 0.1, isMetallic: false)])
        label.position = [0, 0.05, 0.025]
        label.scale = [0.0014, 0.0014, 0.0014]
        body.addChild(label)
        return body
    }

    private func makePinnedEntity(for note: VisionPinnedNote) -> Entity {
        let card = ModelEntity(mesh: .generatePlane(width: 0.24, height: 0.14, cornerRadius: 0.03), materials: [SimpleMaterial(color: UIColor(white: 1.0, alpha: 0.28), roughness: 0.2, isMetallic: false)])
        card.generateCollisionShapes(recursive: true)
        card.components.set(InputTargetComponent())

        let text = ModelEntity(mesh: MeshResource.generateText(note.text, extrusionDepth: 0.001, font: .systemFont(ofSize: 0.055, weight: .regular), containerFrame: CGRect(x: -0.11, y: -0.055, width: 0.22, height: 0.11), alignment: .left, lineBreakMode: .byWordWrapping), materials: [SimpleMaterial(color: .white, roughness: 0.1, isMetallic: false)])
        text.position = [0, 0, 0.01]
        text.scale = [0.0013, 0.0013, 0.0013]
        card.addChild(text)
        return card
    }

    private func updatePinnedText(for entity: Entity, text: String) {
        guard let card = entity.children.first as? ModelEntity else { return }
        card.model = ModelComponent(mesh: MeshResource.generateText(text, extrusionDepth: 0.001, font: .systemFont(ofSize: 0.055, weight: .regular), containerFrame: CGRect(x: -0.11, y: -0.055, width: 0.22, height: 0.11), alignment: .left, lineBreakMode: .byWordWrapping), materials: [SimpleMaterial(color: .white, roughness: 0.1, isMetallic: false)])
    }
}
#endif
