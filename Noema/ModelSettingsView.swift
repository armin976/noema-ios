// ModelSettingsView.swift
import SwiftUI
import UIKit

struct ModelSettingsView: View {
    let model: LocalModel
    @EnvironmentObject var modelManager: AppModelManager
    @EnvironmentObject var vm: ChatVM
    @AppStorage("isAdvancedMode") private var isAdvancedMode = false
    @AppStorage("defaultModelPath") private var defaultModelPath = ""
    @State private var settings = ModelSettings()
    @State private var layerCount: Int = 0
    @State private var scanning = false
    @State private var showKInfo = false
    // V-cache quantization disabled
    // @State private var showVInfo = false
    @State private var showDeleteConfirm = false
    @State private var usingDefaultGPULayers = false
    @Environment(\.dismiss) private var dismiss
    let loadAction: (ModelSettings) -> Void
    // File status (GGUF)
    @State private var weightsFilePath: String? = nil
    @State private var mmprojFilePath: String? = nil
    @State private var mmprojChecked: Bool = false
    @State private var filesStatusLoaded: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(model.format.rawValue)) {
                    if model.format == .slm {
                        Text("Context Length: 4096 tokens")
                    } else {
                        Slider(value: $settings.contextLength, in: 512...32768, step: 256) {
                            Text("Context Length")
                        }
                        Text("\(Int(settings.contextLength)) tokens")
                        // Live RAM estimate for the chosen context
                        ramEstimateView()
                        if settings.contextLength > 8192 {
                            Text("High context lengths use more memory")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    Toggle("Use as Default Model", isOn: Binding(
                        get: { defaultModelPath == model.url.path },
                        set: { newVal in
                            if newVal {
                                defaultModelPath = model.url.path
                            } else if defaultModelPath == model.url.path {
                                defaultModelPath = ""
                            }
                        }
                    ))
                }

                if model.format == .gguf {
                    ggufSettings
                } else {
                    mlxSettings
                }
                Section {
                    Button("Reset to Default Settings") {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        settings = ModelSettings.default(for: model.format)
                        // For GGUF, default to all layers by using sentinel
                        if model.format == .gguf { settings.gpuLayers = -1 }
                    }
                    .disabled(vm.loading)
                    
                    Button("Delete Model", role: .destructive) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        showDeleteConfirm = true
                    }
                }
                // Files status (bottom area)
                if model.format == .gguf {
                    Section("Files") {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: (weightsFilePath != nil) ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle((weightsFilePath != nil) ? .green : .red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Weights")
                                Text(weightsFilePath ?? "Not found")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        HStack(alignment: .top, spacing: 8) {
                            let projectorIcon: String = {
                                if mmprojFilePath != nil { return "checkmark.circle.fill" }
                                return mmprojChecked ? "xmark.circle" : "questionmark.circle"
                            }()
                            let projectorColor: Color = {
                                if mmprojFilePath != nil { return .green }
                                return mmprojChecked ? .orange : .secondary
                            }()
                            Image(systemName: projectorIcon)
                                .foregroundStyle(projectorColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Projector (mmproj)")
                                Text(mmprojFilePath ?? (mmprojChecked ? "Not provided by repository" : "Unknown (not checked yet)"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { hideKeyboard() }
            .navigationTitle(model.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Back", systemImage: "chevron.backward")
                    }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        // Save only; do not load. Close sheet.
                        modelManager.updateSettings(settings, for: model)
                        dismiss()
                    }) {
                        Text("Save")
                            .foregroundColor(.primary)
                            .opacity(0.6)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        // Persist settings and trigger load
                        modelManager.updateSettings(settings, for: model)
                        loadAction(settings)
                        dismiss()
                    }) {
                        if vm.loading { ProgressView() } else { Text("Load") }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(vm.loading)
                }
            }
            .onAppear {
                usingDefaultGPULayers = modelManager.modelSettings[model.url.path] == nil
                settings = modelManager.settings(for: model)
                layerCount = model.totalLayers
                if layerCount == 0 {
                    scanning = true
                    Task.detached {
                        let count = ModelScanner.layerCount(for: model.url, format: model.format)
                        await MainActor.run {
                            layerCount = count
                            scanning = false
                            updateGPULayers()
                        }
                    }
                } else {
                    updateGPULayers()
                }
                refreshFileStatuses()
            }
            .onChange(of: layerCount) { _ in updateGPULayers() }
            .onChange(of: settings.gpuLayers) { _ in usingDefaultGPULayers = false }
            .alert("K Cache Quantization", isPresented: $showKInfo) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Quantize the runtime key cache to save memory. Experimental.")
            }
            .alert("Delete \(model.name)?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    Task {
                        if modelManager.loadedModel?.id == model.id {
                            await vm.unload()
                        }
                        modelManager.delete(model)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) { showDeleteConfirm = false }
            }
        }
    }

    @ViewBuilder
    private func ramEstimateView() -> some View {
        let sizeBytes = Int64(model.sizeGB * 1_073_741_824.0)
        let ctx = Int(settings.contextLength)
        let (estimate, budget) = ModelRAMAdvisor.estimateAndBudget(format: model.format, sizeBytes: sizeBytes, contextLength: ctx, layerCount: (layerCount > 0 ? layerCount : nil))
        let estStr = ByteCountFormatter.string(fromByteCount: estimate, countStyle: .memory)
        let budStr = budget.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .memory) } ?? "--"
        let maxCtx = ModelRAMAdvisor.maxContextUnderBudget(format: model.format, sizeBytes: sizeBytes, layerCount: (layerCount > 0 ? layerCount : nil))
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: (budget == nil || estimate <= (budget ?? Int64.max)) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor((budget == nil || estimate <= (budget ?? Int64.max)) ? .green : .orange)
                Text("Estimated working set: \(estStr) · Budget: \(budStr)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let maxCtx {
                HStack(spacing: 8) {
                    Image(systemName: "gauge")
                        .foregroundColor(.secondary)
                    Text("Max recommended context on this device: ~\(maxCtx) tokens")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private var ggufSettings: some View {
        Section("GGUF") {
            Toggle("Keep Model In Memory", isOn: $settings.keepInMemory)
            if scanning {
                VStack(alignment: .leading) { ProgressView() }
            } else if DeviceGPUInfo.supportsGPUOffload {
                VStack(alignment: .leading) {
                    // Represent sentinel (-1) as layerCount+1 on slider to show "All"
                    Slider(value: Binding(get: {
                        Double(settings.gpuLayers < 0 ? (layerCount + 1) : settings.gpuLayers)
                    }, set: { newVal in
                        let v = Int(newVal)
                        if v >= layerCount + 1 {
                            settings.gpuLayers = -1
                        } else {
                            settings.gpuLayers = max(0, min(layerCount, v))
                        }
                    }), in: 0...Double(layerCount + 1), step: 1)
                    Text(settings.gpuLayers < 0 ? "GPU Offload Layers: All/\(layerCount)" : "GPU Offload Layers: \(settings.gpuLayers)/\(layerCount)")
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("This device doesn't support GPU offload.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.yellow.opacity(0.1))
            }
            if isAdvancedMode {
                Stepper("CPU Threads: \(settings.cpuThreads)", value: $settings.cpuThreads, in: 1...ProcessInfo.processInfo.activeProcessorCount)
                if DeviceGPUInfo.supportsGPUOffload {
                    Toggle("Offload KV Cache to GPU", isOn: $settings.kvCacheOffload)
                }
                Toggle("Use mmap()", isOn: $settings.useMmap)
                HStack {
                    Text("Seed")
                    TextField("Random", text: Binding(
                        get: { settings.seed.map(String.init) ?? "" },
                        set: { newVal in
                            // Strip non-digits; drop punctuation
                            let digits = newVal.filter { $0.isNumber }
                            if let val = Int(digits) { settings.seed = val } else { settings.seed = nil }
                        }
                    ))
                    .keyboardType(.numberPad)
                }
                
                Picker(selection: $settings.kCacheQuant) {
                    ForEach(CacheQuant.allCases) { q in
                        Text(q.rawValue).tag(q)
                    }
                } label: {
                    HStack {
                        Text("K Cache Quant")
                        Button {
                            showKInfo = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .pickerStyle(.menu)
                .help("Quantize the runtime key cache to save memory. Experimental.")

                // V-cache quantization is disabled; hide picker
            }
        }
    }

    @ViewBuilder
    private var mlxSettings: some View {
        Section("MLX") {
            Text("GPU off-load is not supported for this model.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if isAdvancedMode {
                HStack {
                    Text("Seed")
                    TextField("Random", text: Binding(
                        get: { settings.seed.map(String.init) ?? "" },
                        set: { newVal in
                            let digits = newVal.filter { $0.isNumber }
                            if let val = Int(digits) { settings.seed = val } else { settings.seed = nil }
                        }
                    ))
                    .keyboardType(.numberPad)
                }
                TextField("Tokenizer Path (tokenizer.json)", text: Binding(
                    get: { settings.tokenizerPath ?? "" },
                    set: { settings.tokenizerPath = $0.isEmpty ? nil : $0 }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.caption)
            }
        }
    }
}

private extension ModelSettingsView {
    func updateGPULayers() {
        if !DeviceGPUInfo.supportsGPUOffload {
            settings.gpuLayers = 0
            settings.kvCacheOffload = false
            return
        }
        if model.format == .gguf {
            if layerCount > 0 {
                // Preserve sentinel (-1) meaning all layers
                if settings.gpuLayers >= 0 && settings.gpuLayers > layerCount {
                    settings.gpuLayers = layerCount
                }
                if usingDefaultGPULayers && settings.gpuLayers == 0 {
                    // Default to all layers when unset
                    settings.gpuLayers = -1
                }
            }
        } else {
            settings.gpuLayers = 0
        }
    }
    
    func refreshFileStatuses() {
        guard model.format == .gguf else { return }
        let dir = model.url.deletingLastPathComponent()
        let artifactsURL = dir.appendingPathComponent("artifacts.json")
        var weightsName: String? = nil
        var projector: Any? = nil
        var checked = false
        if let data = try? Data(contentsOf: artifactsURL),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            weightsName = obj["weights"] as? String
            projector = obj["mmproj"]
            checked = (obj["mmprojChecked"] as? Bool) ?? false
        }
        // Resolve weights path
        var resolvedWeights: String? = nil
        if let w = weightsName {
            let p = dir.appendingPathComponent(w).path
            if FileManager.default.fileExists(atPath: p) { resolvedWeights = p }
        } else {
            let p = model.url.path
            if FileManager.default.fileExists(atPath: p) { resolvedWeights = p }
        }
        // Resolve projector path
        var resolvedProj: String? = nil
        if let s = projector as? String {
            let p = dir.appendingPathComponent(s).path
            if FileManager.default.fileExists(atPath: p) { resolvedProj = p }
        }
        weightsFilePath = resolvedWeights
        mmprojFilePath = resolvedProj
        mmprojChecked = checked
        filesStatusLoaded = true
    }
}
