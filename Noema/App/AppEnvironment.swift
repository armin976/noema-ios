import Combine
import Foundation
import SwiftUI
import UIKit
#if canImport(MLX)
import MLX
#endif

enum TabBarMinimizeBehavior { case none, onScrollDown }
extension View {
    func tabBarMinimizeBehavior(_ behavior: TabBarMinimizeBehavior) -> some View { self }
    func tabViewBottomAccessory(alignment: Alignment = .center, @ViewBuilder content: () -> some View) -> some View { self }
}

enum ModelKind { case gemma, llama3, qwen, smol, lfm, mistral, phi, internlm, deepseek, yi, other
    static func detect(id: String) -> ModelKind {
        let s = id.lowercased()
        if s.contains("gemma") { return .gemma }
        if s.contains("llama-3") || s.contains("llama3") { return .llama3 }
        if s.contains("lfm2") || s.contains("liquid") { return .lfm }
        if s.contains("smol") { return .smol }
        if s.contains("internlm") { return .internlm }
        if s.contains("deepseek") { return .deepseek }
        if s.contains("yi") { return .yi }
        if s.contains("qwen") || s.contains("mpt") {
            return .qwen
        }
        if s.contains("llama-2") || s.contains("llama2") { return .mistral }
        if s.contains("mistral") || s.contains("mixtral") { return .mistral }
        if s.contains("phi-3") || s.contains("phi3") { return .phi }
        return .other
    }
}

enum RunPurpose { case chat, title }

final class AppExperienceCoordinator: ObservableObject {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Published var showOnboarding: Bool
    @Published var showShortcutHelp = false
    @Published private(set) var isFirstLaunch: Bool

    init() {
        let firstRun = !hasCompletedOnboarding
        self.isFirstLaunch = firstRun
        self.showOnboarding = firstRun
    }

    func markOnboardingComplete() {
        hasCompletedOnboarding = true
        isFirstLaunch = false
        showOnboarding = false
    }

    func reopenOnboarding() {
        showOnboarding = true
    }

    func presentShortcutHelp() {
        showShortcutHelp = true
    }

    func dismissShortcutHelp() {
        showShortcutHelp = false
    }
}

private enum ModelInfo {
    static let repoID   = "ggml-org/Qwen3-1.7B-GGUF"
    static let fileName = "Qwen3-1.7B-Q4_K_M.gguf"

    /// Returns <Documents>/LocalLLMModels/qwen/Qwen3-1.7B-GGUF/…/Qwen3‑1.7B‑Q4_K_M.gguf
    static func sandboxURL() -> URL {
        var url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalLLMModels", isDirectory: true)
        for comp in repoID.split(separator: "/") {
            url.appendPathComponent(String(comp), isDirectory: true)
        }
        return url.appendingPathComponent(fileName)
    }
}

@MainActor
final class ModelDownloader: ObservableObject {
    enum State: Equatable {
        case idle
        case downloading(Double)
        case finished
        case failed(String)
    }

    @Published var state: State = .idle
    @AppStorage("verboseLogging") private var verboseLogging = false

    /// Additional files some models may ship alongside the GGUF.
    /// These are optional so the downloader succeeds even if they are absent.
    private static let extraFiles: [String] = []
    private var fractions: [Double] = []

    init() {
        let modelOK  = FileManager.default.fileExists(atPath: ModelInfo.sandboxURL().path)
        let sideOK   = Self.extraFiles.allSatisfy { name in
            FileManager.default.fileExists(atPath: ModelInfo.sandboxURL()
                .deletingLastPathComponent()
                .appendingPathComponent(name).path)
        }
        state = (modelOK && sideOK) ? .finished : .idle
        if verboseLogging { print("[Downloader] init → state = \(state)") }
        if verboseLogging {
            if let metallib = Bundle.main.path(forResource: "default", ofType: "metallib") {
                print("[Startup] default.metallib found: \(metallib)")
            } else {
                print("[Startup] Warning: default.metallib not found. GPU will be disabled and CPU fallback used.")
            }
        }
    }

    func start() {
        guard state == .idle || state.isFailed else { return }
        if verboseLogging { print("[Downloader] starting…") }
        state = .downloading(0)

        let llmDir   = ModelInfo.sandboxURL().deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: llmDir, withIntermediateDirectories: true)
        } catch {
            state = .failed("mkdir: \(error.localizedDescription)")
            return
        }

        var items: [(repo: String, file: String, dest: URL)] = []
        items.append((ModelInfo.repoID, ModelInfo.fileName, llmDir.appendingPathComponent(ModelInfo.fileName)))
        items += Self.extraFiles.map { (ModelInfo.repoID, $0, llmDir.appendingPathComponent($0)) }

        let total = Double(items.count)
        fractions = Array(repeating: 0.0, count: items.count)

        Task {
            for (idx, item) in items.enumerated() {
                let remote  = URL(string: "https://huggingface.co/\(item.repo)/resolve/main/\(item.file)?download=1")!
                let dest    = item.dest

                if verboseLogging { print("[Downloader] ▶︎ \(item.file)") }
                do {
                    try await BackgroundDownloadManager.shared.download(from: remote, to: dest) { part in
                        Task { @MainActor in
                            self.fractions[idx] = part
                            if self.state.isDownloading {
                                self.state = .downloading(self.fractions.reduce(0, +) / total)
                            }
                        }
                    }
                    await MainActor.run {
                        if verboseLogging { print("[Downloader] ✓ \(item.file)") }
                    }
                } catch {
                    await MainActor.run {
                        self.state = .failed(error.localizedDescription)
                        if verboseLogging { print("[Downloader] ❌ \(item.file): \(error.localizedDescription)") }
                    }
                    return
                }
            }

            await MainActor.run {
                self.state = .finished
                if verboseLogging { print("[Downloader] all files done ✅") }
            }
        }
    }
}

private extension ModelDownloader.State {
    var isFailed: Bool       { if case .failed = self { true } else { false } }
    var isDownloading: Bool  { if case .downloading = self { true } else { false } }
}

@MainActor
final class AppEnvironment: ObservableObject {
    let experience = AppExperienceCoordinator()
    let tabRouter = TabRouter()
    let chatVM = ChatVM()
    let modelManager = AppModelManager()
    let datasetManager = DatasetManager()
    let downloadController = DownloadController()
    let inspectorController = InspectorController()

    @AppStorage("appearance") private var appearance = "system"

    var preferredColorScheme: ColorScheme? {
        switch appearance {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil
        }
    }

    init() {
#if canImport(MLX)
        if !DeviceGPUInfo.supportsGPUOffload {
            Device.setDefault(device: Device(.cpu))
        }
#endif
        Task { @MainActor in
            await ToolRegistrar.shared.initializeTools()
        }
        MathRenderTuning.inlineInsets = UIEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
        MathRenderTuning.blockInsets = UIEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
        RevenueCatManager.configure()
        Task { @MainActor in
            await RevenueCatManager.shared.refreshEntitlements()
        }
        let off = UserDefaults.standard.object(forKey: "offGrid") as? Bool ?? false
        NetworkKillSwitch.setEnabled(off)
    }
}

extension FileManager {
    func removeItemIfExists(at url: URL) throws {
        if fileExists(atPath: url.path) { try removeItem(at: url) }
    }

    @discardableResult
    func moveItemReplacing(at dest: URL, from src: URL) throws -> URL {
        try removeItemIfExists(at: dest)
        try moveItem(at: src, to: dest)
        return dest
    }
}
