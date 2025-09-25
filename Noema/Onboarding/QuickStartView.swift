import SwiftUI

struct QuickStartInstaller {
    struct InstallResult { let preset: ModelPreset }

    let install: @Sendable (ModelPreset) async throws -> InstallResult
    let importSample: @Sendable () async throws -> URL

    init(install: @escaping @Sendable (ModelPreset) async throws -> InstallResult,
         importSample: @escaping @Sendable () async throws -> URL) {
        self.install = install
        self.importSample = importSample
    }

    static func resolveFromEnvironment() -> QuickStartInstaller {
        let env = ProcessInfo.processInfo.environment
        if env["UITEST_QUICKSTART_MOCK"] == "1" {
            return .mock()
        }
        return .live()
    }

    static func live(fileManager: FileManager = .default) -> QuickStartInstaller {
        QuickStartInstaller { preset in
            _ = preset
            try await Task.sleep(nanoseconds: 350_000_000)
            return InstallResult(preset: preset)
        } importSample: {
            let data = try sampleData()
            let destination = try writeSample(data: data, fileManager: fileManager)
            return destination
        }
    }

    static func mock(fileManager: FileManager = .default) -> QuickStartInstaller {
        QuickStartInstaller { preset in
            _ = preset
            try await Task.sleep(nanoseconds: 50_000_000)
            return InstallResult(preset: preset)
        } importSample: {
            if let data = try? sampleData() {
                return try writeSample(data: data, fileManager: fileManager)
            }
            let fallback = "question,answer\nWhat is Noema?,An on-device AI assistant.\n"
            return try writeSample(data: Data(fallback.utf8), fileManager: fileManager)
        }
    }

    private static func sampleData() throws -> Data {
        let bundles = [Bundle.main, Bundle(for: QuickStartBundleMarker.self)]
        for bundle in bundles {
            if let url = bundle.url(forResource: "sample", withExtension: "csv", subdirectory: "Fixtures") ??
                bundle.url(forResource: "sample", withExtension: "csv") {
                return try Data(contentsOf: url)
            }
        }
        let fallback = "question,answer\nWhat is Noema?,An on-device private AI assistant.\n"
        guard let data = fallback.data(using: .utf8) else { throw QuickStartError.sampleMissing }
        return data
    }

    private static func writeSample(data: Data, fileManager: FileManager) throws -> URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let quickStartDir = docs.appendingPathComponent("QuickStartSamples", isDirectory: true)
        if !fileManager.fileExists(atPath: quickStartDir.path) {
            try fileManager.createDirectory(at: quickStartDir, withIntermediateDirectories: true)
        }
        let destination = quickStartDir.appendingPathComponent("sample.csv")
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try data.write(to: destination, options: .atomic)
        return destination
    }
}

private final class QuickStartBundleMarker {}

enum QuickStartError: LocalizedError {
    case sampleMissing
    case cancelled

    var errorDescription: String? {
        switch self {
        case .sampleMissing:
            return "Could not find the bundled sample dataset."
        case .cancelled:
            return "The quick start flow was cancelled."
        }
    }
}

struct QuickStartView: View {
    private enum Stage {
        case selecting
        case installing
        case installed
        case importing
        case imported
    }

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPreset: ModelPreset
    @State private var stage: Stage = .selecting
    @State private var privacyEnabled = true
    @State private var importedURL: URL?
    @State private var errorWrapper: IdentifiableError?

    let installer: QuickStartInstaller

    init(installer: QuickStartInstaller? = nil) {
        let resolved = installer ?? QuickStartInstaller.resolveFromEnvironment()
        self.installer = resolved
        _selectedPreset = State(initialValue: ModelPresets.recommendedPreset())
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Form {
                    Section("Device preset") {
                        Picker("Preset", selection: $selectedPreset) {
                            ForEach(ModelPresets.presetsSorted()) { preset in
                                Text("\(preset.title) — \(preset.quantization)")
                                    .tag(preset)
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("quickstart.presetPicker")

                        Text("Context: \(selectedPreset.contextTokens) tokens")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        Text("Estimated install time: \(selectedPreset.etaDescription)")
                            .font(.callout)
                            .accessibilityIdentifier("quickstart.eta")

                        Button("Smaller & faster") {
                            if let smaller = ModelPresets.nextSmallerPreset(relativeTo: selectedPreset) {
                                selectedPreset = smaller
                            }
                        }
                        .disabled(ModelPresets.nextSmallerPreset(relativeTo: selectedPreset) == nil)
                        .accessibilityIdentifier("quickstart.smaller")
                    }

                    Section("Privacy") {
                        Toggle(isOn: $privacyEnabled) {
                            Text("Keep everything on this device")
                        }
                        .toggleStyle(.switch)
                        .accessibilityIdentifier("quickstart.privacyToggle")
                        Text("Noema stays offline by default. You can enable online features later.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section("Status") {
                        Text(statusMessage)
                            .accessibilityIdentifier("quickstart.status")
                        if let importedURL {
                            Text("Sample imported: \(importedURL.lastPathComponent)")
                                .font(.footnote)
                                .accessibilityIdentifier("quickstart.sampleLabel")
                        }
                    }
                }
                .disabled(stage == .installing || stage == .importing)

                VStack(spacing: 12) {
                    Button(action: startInstall) {
                        if stage == .installing {
                            ProgressView()
                        } else {
                            Text("Install preset")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(stage != .selecting)
                    .accessibilityIdentifier("quickstart.install")

                    Button(action: startImport) {
                        if stage == .importing {
                            ProgressView()
                        } else {
                            Text("Import sample dataset")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(stage != .installed)
                    .accessibilityIdentifier("quickstart.import")

                    Button("Finish") {
                        dismiss()
                    }
                    .disabled(stage != .imported)
                    .accessibilityIdentifier("quickstart.finish")
                }
                .padding(.horizontal)
            }
            .padding()
            .navigationTitle("Quick Start")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("quickstart.sheet")
        .alert(item: $errorWrapper) { wrapper in
            Alert(title: Text("Quick Start"), message: Text(wrapper.message), dismissButton: .default(Text("OK")))
        }
    }

    private var statusMessage: String {
        switch stage {
        case .selecting:
            return "Choose a preset and install the recommended model."
        case .installing:
            return "Installing \(selectedPreset.title)…"
        case .installed:
            return "Model ready. Import the sample dataset next."
        case .importing:
            return "Importing sample.csv…"
        case .imported:
            return "Setup complete. You can start chatting now."
        }
    }

    private func startInstall() {
        guard stage == .selecting else { return }
        stage = .installing
        let preset = selectedPreset
        Task {
            do {
                _ = try await installer.install(preset)
                await MainActor.run {
                    stage = .installed
                }
            } catch {
                await handle(error: error, resetStage: .selecting)
            }
        }
    }

    private func startImport() {
        guard stage == .installed else { return }
        stage = .importing
        Task {
            do {
                let url = try await installer.importSample()
                await MainActor.run {
                    importedURL = url
                    stage = .imported
                }
            } catch {
                await handle(error: error, resetStage: .installed)
            }
        }
    }

    @MainActor
    private func handle(error: Error, resetStage: Stage) {
        stage = resetStage
        errorWrapper = IdentifiableError(message: error.localizedDescription)
    }
}

private struct IdentifiableError: Identifiable {
    let id = UUID()
    let message: String
}
