// LocalDatasetDetailView.swift
import SwiftUI
import UIKit

struct LocalDatasetDetailView: View {
    let dataset: LocalDataset
    @EnvironmentObject var modelManager: AppModelManager
    @EnvironmentObject var datasetManager: DatasetManager
    @EnvironmentObject var chatVM: ChatVM
    @Environment(\.dismiss) private var dismiss

    @State private var files: [(name: String, size: String)] = []
    @State private var tokenEstimate: String = ""
    @State private var isEstimatingTokens = false
    @State private var compressedMB: String = ""
    @State private var warmingUpEmbed = false
    @State private var embedReady = false
    @State private var embedProgress: Double = 0.0
    @State private var embedStatusMessage = ""
    @StateObject private var embedInstaller = EmbedModelInstaller()
    @State private var showStartOnBatteryConfirm = false
    @State private var showConfirmOnBatteryConfirm = false
    @State private var showDisabledUseReason = false

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Dataset Info")) {
                    Text(dataset.datasetID)
                    HStack {
                        Text("Source")
                        Spacer()
                        Text(dataset.source)
                    }
                    HStack {
                        Text("Downloaded")
                        Spacer()
                        Text(dateFormatter.string(from: dataset.downloadDate))
                    }
                    HStack {
                        Text("Size")
                        Spacer()
                        Text(String(format: "%.1f MB", dataset.sizeMB))
                    }
                    if !compressedMB.isEmpty {
                        HStack {
                            Text("Compressed Text")
                            Spacer()
                            Text(compressedMB)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !tokenEstimate.isEmpty || isEstimatingTokens {
                        HStack {
                            Text("Approx. Tokens")
                            Spacer()
                            if isEstimatingTokens {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    Text(tokenEstimate.isEmpty ? "…" : tokenEstimate)
                                }
                            } else {
                                Text(tokenEstimate)
                            }
                        }
                    }
                }
                Section(header: Text("Preparation")) {
                    let status = datasetManager.processingStatus[dataset.datasetID]
                    if let s = status, s.stage != .completed {
                        VStack(alignment: .leading, spacing: 12) {
                            // Stage indicator with steps
                            HStack(spacing: 12) {
                                ForEach(Array([DatasetProcessingStage.extracting, .compressing, .embedding].enumerated()), id: \.offset) { index, stage in
                                    VStack(spacing: 4) {
                                        Circle()
                                            .fill(currentStageColor(stage, current: s.stage))
                                            .frame(width: 20, height: 20)
                                            .overlay(
                                                Circle()
                                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                            )
                                        Text(stageLabel(stage))
                                            .font(.caption2)
                                            .multilineTextAlignment(.center)
                                            .foregroundStyle(s.stage == stage ? .primary : .secondary)
                                    }
                                    if index < 2 {
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(height: 2)
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                            }
                            
                            // Progress details
                            HStack {
                                if s.stage == .embedding {
                                    HStack(spacing: 6) {
                                        Text("Embedding")
                                            .font(.headline)
                                            .bold()
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    }
                                } else if s.stage == .failed {
                                    Text(s.message ?? stageLabel(s.stage))
                                        .font(.headline)
                                } else {
                                    Text(stageLabel(s.stage))
                                        .font(.headline)
                                }
                                Spacer()
                                let eta: String = {
                                    if let e = s.etaSeconds, e > 0 {
                                        let mins = Int(e) / 60
                                        let secs = Int(e) % 60
                                        return String(format: "~%dm %02ds", mins, secs)
                                    } else { return "…" }
                                }()
                                Text("\(Int(s.progress * 100))% · \(eta)")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            
                            ProgressView(value: s.progress)
                                .progressViewStyle(.linear)
                                .tint(.blue)
                                
                            if let msg = s.message, !msg.isEmpty {
                                Text(msg)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            // Gate to confirm starting embeddings when paused at the embedding step
                            if s.stage == .embedding && s.progress <= 0.0001 {
                                VStack(alignment: .leading, spacing: 8) {
                                    Button {
                                        if isPluggedIn() {
                                            Task {
                                                await chatVM.unload()
                                                datasetManager.startEmbeddingForID(dataset.datasetID)
                                            }
                                        } else {
                                            showConfirmOnBatteryConfirm = true
                                        }
                                    } label: {
                                        Text("Confirm and Start Embedding")
                                            .font(.subheadline)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .confirmationDialog("Proceed on battery power?", isPresented: $showConfirmOnBatteryConfirm, titleVisibility: .visible) {
                                        Button("Proceed") {
                                            Task {
                                                await chatVM.unload()
                                                datasetManager.startEmbeddingForID(dataset.datasetID)
                                            }
                                        }
                                        Button("Cancel", role: .cancel) {}
                                    } message: {
                                        Text("Embedding is resource intensive. For best performance, plug in your phone. Do you want to proceed on battery?")
                                    }
                                    Text("For best performance, please plug in your phone until this completes.")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Button("Stop", role: .destructive) {
                                datasetManager.cancelProcessingForID(dataset.datasetID)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 4)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            if warmingUpEmbed {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        let isDownloading = embedStatusMessage.contains("Downloading")
                                        Image(systemName: isDownloading ? "arrow.down.circle.fill" : "cpu")
                                            .foregroundColor(.blue)
                                            .symbolEffect(isDownloading ? .pulse.byLayer : .pulse)
                                        Text("Preparing Embedding Model")
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                    }
                                    
                                    ProgressView(value: embedProgress)
                                        .progressViewStyle(.linear)
                                        .tint(.blue)
                                    
                                    if !embedStatusMessage.isEmpty {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(embedStatusMessage)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            
                                            if embedStatusMessage.contains("Downloading") && embedStatusMessage.contains("model") {
                                                HStack {
                                                    Image(systemName: "info.circle")
                                                        .font(.caption2)
                                                    Text("First-time download from HuggingFace")
                                                        .font(.caption2)
                                                        .foregroundStyle(.tertiary)
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            } else if embedReady && modelManager.activeDataset?.datasetID == dataset.datasetID {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .symbolEffect(.bounce, value: embedReady)
                                    Text("Embedding Model Ready")
                                        .font(.headline)
                                        .foregroundColor(.green)
                                }
                            } else {
                                // Show ready indicator only if dataset is fully indexed
                                let isReady = dataset.isIndexed || (datasetManager.processingStatus[dataset.datasetID]?.stage == .completed)
                                if isReady {
                                    Label("Ready for Use", systemImage: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                            
                            if !warmingUpEmbed {
                                Text("RAG embeds normalized paragraphs from your PDFs and EPUBs. On each question, the most relevant chunks are retrieved and added to the prompt. Images are ignored.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)
                            }
                            // Only show manual start when not yet indexed/embedded and no active processing
                            let isReady = dataset.isIndexed || (datasetManager.processingStatus[dataset.datasetID]?.stage == .completed)
                            if !isReady {
                                Button("Start Embedding Process") {
                                    if isPluggedIn() {
                                        Task {
                                            await chatVM.unload()
                                            datasetManager.startEmbeddingForID(dataset.datasetID)
                                        }
                                    } else {
                                        showStartOnBatteryConfirm = true
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .confirmationDialog("Proceed on battery power?", isPresented: $showStartOnBatteryConfirm, titleVisibility: .visible) {
                                    Button("Proceed") {
                                        Task {
                                            await chatVM.unload()
                                            datasetManager.startEmbeddingForID(dataset.datasetID)
                                        }
                                    }
                                    Button("Cancel", role: .cancel) {}
                                } message: {
                                    Text("Embedding is resource intensive. For best performance, plug in your phone. Do you want to proceed on battery?")
                                }
                            }
                        }
                    }
                }
                if !files.isEmpty {
                    Section(header: Text("Files")) {
                        ForEach(files, id: \.name) { file in
                            let fileURL = URL(fileURLWithPath: file.name, relativeTo: dataset.url)
                            NavigationLink(destination: DatasetFileViewer(url: fileURL)) {
                                HStack {
                                    Text(file.name)
                                    Spacer()
                                    Text(file.size)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Section {
                    let isCurrentlyIndexing = datasetManager.indexingDatasetID == dataset.datasetID
                    let hasVectors = FileManager.default.fileExists(atPath: dataset.url.appendingPathComponent("vectors.json").path)
                    let needsIndexing = !(dataset.isIndexed || hasVectors || (datasetManager.processingStatus[dataset.datasetID]?.stage == .completed))
                    let isReady = (dataset.isIndexed || hasVectors) || (datasetManager.processingStatus[dataset.datasetID]?.stage == .completed)
                    let disabledForSLM = chatVM.isSLMModel
                    if modelManager.activeDataset?.datasetID == dataset.datasetID {
                        Button("Stop Using Dataset") {
                            chatVM.setDatasetForActiveSession(nil)
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    } else {
                        if needsIndexing && !isCurrentlyIndexing {
                            Button("Index Dataset") {
                                Task {
                                    await chatVM.unload()
                                    await logger.log("[UI] User tapped Index Dataset for \(dataset.datasetID)")
                                    datasetManager.ensureIndexedForID(dataset.datasetID)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                        } else if isReady {
                            if disabledForSLM {
                                Button("Use Dataset") { }
                                    .buttonStyle(.bordered)
                                    .frame(maxWidth: .infinity)
                                    .disabled(true)
                                    .overlay(
                                        Color.clear
                                            .contentShape(Rectangle())
                                            .onTapGesture { showDisabledUseReason = true }
                                            .allowsHitTesting(true)
                                    )
                            } else {
                                Button("Use Dataset") {
                                    Task { await logger.log("[UI] User tapped Use Dataset for \(dataset.datasetID)") }
                                    chatVM.setDatasetForActiveSession(dataset)
                                    warmingUpEmbed = true
                                    embedProgress = 0.0
                                    Task { await prepareEmbeddingsAndIndex() }
                                }
                                .buttonStyle(.borderedProminent)
                                .frame(maxWidth: .infinity)
                            }
                        } else {
                            Button("Use Dataset") {
                                // Disabled state
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                            .disabled(true)
                            .overlay(
                                Color.clear
                                    .contentShape(Rectangle())
                                    .onTapGesture { showDisabledUseReason = true }
                                    .allowsHitTesting(true)
                            )
                        }
                    }
                    if isCurrentlyIndexing, let s = datasetManager.processingStatus[dataset.datasetID] {
                        VStack(alignment: .center) {
                            ProgressView(value: s.progress)
                                .progressViewStyle(.linear)
                                .tint(.blue)
                            let eta: String = {
                                if let e = s.etaSeconds, e > 0 {
                                    return String(format: "~%dm %02ds", Int(e)/60, Int(e)%60)
                                } else { return "…" }
                            }()
                            Text("Indexing: \(Int(s.progress * 100))% · \(eta)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Button("Delete Dataset", role: .destructive) {
                        try? datasetManager.delete(dataset)
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(dataset.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .alert("Unavailable", isPresented: $showDisabledUseReason) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(disabledUseDatasetReason)
            }
            .task {
                loadFiles()
                await computeCompressedSize()
                // Don't automatically check embedding readiness - only when user presses "Use Dataset"
            }
        }
    }

    @MainActor
    private func prepareEmbeddingsAndIndex() async {
        embedStatusMessage = "Checking embedding model…"
        embedProgress = 0.05
        // Ensure dirs only (no network)
        await EmbeddingModel.shared.ensureModel()
        if !(await EmbeddingModel.shared.isModelAvailable()) {
            embedStatusMessage = "Downloading embedding model…"
            embedProgress = 0.1
            
            // Start a task to monitor download progress
            let progressTask = Task { @MainActor in
                while embedInstaller.state == .downloading || embedInstaller.state == .verifying || embedInstaller.state == .installing {
                    embedProgress = embedInstaller.progress * 0.6 + 0.1 // Scale to 10%-70% range
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                }
            }
            
            await embedInstaller.installIfNeeded()
            progressTask.cancel()
            
            switch embedInstaller.state {
            case .failed(let msg):
                embedStatusMessage = "Failed: \(msg)"
                warmingUpEmbed = false
                return
            case .ready:
                embedProgress = 0.7
                break
            default:
                break
            }
        }
        embedStatusMessage = "Loading model…"
        embedProgress = 0.7
        await EmbeddingModel.shared.warmUp()
        let ready = await EmbeddingModel.shared.isReady()
        if ready {
            embedStatusMessage = "Indexing dataset…"
            embedProgress = 0.85
            await chatVM.unload()
            datasetManager.ensureIndexedForID(dataset.datasetID)
            embedReady = true
            embedProgress = 1.0
        } else {
            embedStatusMessage = "Failed to initialize"
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            warmingUpEmbed = false
            embedStatusMessage = ""
        }
    }

    private func loadFiles() {
        let fm = FileManager.default
        var items: [(name: String, size: String)] = []
        if let enumerator = fm.enumerator(at: dataset.url, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) {
            while let url = enumerator.nextObject() as? URL {
                let base = url.lastPathComponent
                if ["vectors.json", "extracted.txt", "extracted.compact.txt"].contains(base) { continue }
                if let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                   values.isRegularFile == true {
                    let relative = url.path.replacingOccurrences(of: dataset.url.path + "/", with: "")
                    let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(values.fileSize ?? 0), countStyle: .file)
                    items.append((name: relative, size: sizeStr))
                }
            }
        }
        files = items.sorted(by: { $0.name < $1.name })
    }

    private func estimateTokens() async {
        await MainActor.run { isEstimatingTokens = true }
        let tokens = await DatasetRetriever.shared.estimateTokens(in: dataset)
        if tokens > 0 {
            tokenEstimate = NumberFormatter.localizedString(from: NSNumber(value: tokens), number: .decimal)
        }
        await MainActor.run { isEstimatingTokens = false }
    }

    private func computeCompressedSize() async {
        let dir = dataset.url
        let compact = dir.appendingPathComponent("extracted.compact.txt")
        let extracted = dir.appendingPathComponent("extracted.txt")
        let urlToUse: URL? = FileManager.default.fileExists(atPath: compact.path) ? compact : (FileManager.default.fileExists(atPath: extracted.path) ? extracted : nil)
        if let u = urlToUse,
           let attrs = try? FileManager.default.attributesOfItem(atPath: u.path),
           let bytes = attrs[.size] as? NSNumber {
            let mb = Double(truncating: bytes) / 1_048_576.0
            await MainActor.run { compressedMB = String(format: "~%.1f MB", mb) }
        }
    }
    
    private func currentStageColor(_ stage: DatasetProcessingStage, current: DatasetProcessingStage) -> Color {
        switch (stage, current) {
        case (.extracting, .extracting), (.compressing, .compressing), (.embedding, .embedding):
            return .blue
        case (.extracting, .compressing), (.extracting, .embedding), (.compressing, .embedding):
            return .green
        default:
            return .gray.opacity(0.3)
        }
    }
}

private func stageLabel(_ s: DatasetProcessingStage) -> String {
    switch s {
    case .extracting: return "Extracting"
    case .compressing: return "Compressing"
    case .embedding: return "Embedding"
    case .completed: return "Ready"
    case .failed: return "Failed"
    }
}

private let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    return f
}()

private extension LocalDatasetDetailView {
    var disabledUseDatasetReason: String {
        if chatVM.isSLMModel {
            return "SLM models aren't yet RAG compatible."
        }
        if datasetManager.indexingDatasetID == dataset.datasetID {
            return "Dataset is currently indexing. You can use it when indexing completes."
        }
        return "This dataset isn’t ready yet. Please index it first."
    }
}

@MainActor
private func isPluggedIn() -> Bool {
    UIDevice.current.isBatteryMonitoringEnabled = true
    let state = UIDevice.current.batteryState
    return state == .charging || state == .full
}
