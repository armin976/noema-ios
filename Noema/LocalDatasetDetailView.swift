// LocalDatasetDetailView.swift
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct LocalDatasetDetailView: View {
    let dataset: LocalDataset
    @EnvironmentObject var modelManager: AppModelManager
    @EnvironmentObject var datasetManager: DatasetManager
    @EnvironmentObject var chatVM: ChatVM
    @Environment(\.dismiss) private var dismiss
#if os(macOS)
    @Environment(\.macModalDismiss) private var macModalDismiss
#endif
    @Environment(\.locale) private var locale

    @State private var files: [(name: String, size: String)] = []
    @State private var tokenEstimate: String = ""
    @State private var isEstimatingTokens = false
    @State private var compressedMB: String = ""
    @State private var warmingUpEmbed = false
    @State private var embedReady = false
    @State private var embedProgress: Double = 0.0
    @State private var embedStatusMessage = ""
    @State private var embedStatusPhase: EmbedStatusPhase = .idle
    @StateObject private var embedInstaller = EmbedModelInstaller()
    @State private var showStartOnBatteryConfirm = false
    @State private var showConfirmOnBatteryConfirm = false
    @State private var showDisabledUseReason = false
    @State private var disabledUseReason = ""

    private func close() {
#if os(macOS)
        macModalDismiss()
#else
        dismiss()
#endif
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text(dataset.datasetID)
                            .font(.title2)
                            .bold()
                            .multilineTextAlignment(.center)
                        
                        Text(dataset.source)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 20)
                    
                    // Info Card
                VStack(spacing: 16) {
                        let datasetBytes = Int64(dataset.sizeMB * 1_048_576.0)
                        let sizeString = localizedFileSizeString(bytes: datasetBytes, locale: locale)
                        InfoRow(label: String(localized: "Downloaded"), value: formatDate(dataset.downloadDate))
                        Divider()
                        InfoRow(label: String(localized: "Size"), value: sizeString)
                        
                        if !compressedMB.isEmpty {
                            Divider()
                            InfoRow(label: String(localized: "Compressed Text"), value: compressedMB)
                        }
                        
                        if !tokenEstimate.isEmpty || isEstimatingTokens {
                            Divider()
                            HStack {
                                Text(LocalizedStringKey("Approx. Tokens"))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if isEstimatingTokens {
                                    HStack(spacing: 6) {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                        Text(tokenEstimate.isEmpty ? "…" : tokenEstimate)
                                    }
                                } else {
                                    Text(tokenEstimate)
                                        .bold()
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(cardBackgroundColor) // Use system background color
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                    .padding(.horizontal)
                    
                    // Preparation Card
                    VStack(alignment: .leading, spacing: 16) {
                        Text(LocalizedStringKey("Preparation"))
                            .font(.headline)
                            .padding(.bottom, 4)
                        
                        let status = datasetManager.processingStatus[dataset.datasetID]
                        if let s = status, s.stage != .completed {
                            processingView(status: s)
                        } else {
                            readyView()
                        }
                    }
                    .padding(16)
                    .background(cardBackgroundColor)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                    .padding(.horizontal)
                    
                    // Files Card
                    if !files.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(LocalizedStringKey("Files"))
                                .font(.headline)
                                .padding(.bottom, 4)
                            
                            ForEach(files, id: \.name) { file in
                                let fileURL = URL(fileURLWithPath: file.name, relativeTo: dataset.url)
                                NavigationLink(destination: DatasetFileViewer(url: fileURL)) {
                                    HStack {
                                        Image(systemName: "doc.text")
                                            .foregroundStyle(.blue)
                                        Text(file.name)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Text(file.size)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Image(systemName: "chevron.right")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                
                                if file.name != files.last?.name {
                                    Divider()
                                }
                            }
                        }
                        .padding(16)
                        .background(cardBackgroundColor)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                        .padding(.horizontal)
                    }
                    
                    // Actions
                    VStack(spacing: 12) {
                        let isCurrentlyIndexing = datasetManager.indexingDatasetID == dataset.datasetID
                        let hasVectors = FileManager.default.fileExists(atPath: dataset.url.appendingPathComponent("vectors.json").path)
                        let isReady = (dataset.isIndexed || hasVectors) || (datasetManager.processingStatus[dataset.datasetID]?.stage == .completed)
                        let disabledForSLM = chatVM.isSLMModel
                        
                        if modelManager.activeDataset?.datasetID == dataset.datasetID {
                            Button {
                                chatVM.setDatasetForActiveSession(nil)
                                close()
                            } label: {
                                Text(LocalizedStringKey("Stop Using Dataset"))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        } else {
                            Button {
                                if isReady {
                                    if !disabledForSLM {
                                        Task { await logger.log("[UI] User tapped Use Dataset for \(dataset.datasetID)") }
                                        chatVM.setDatasetForActiveSession(dataset)
                                        warmingUpEmbed = true
                                        embedProgress = 0.0
                                        Task { await prepareEmbeddingsAndIndex() }
                                    } else {
                                        disabledUseReason = slmUseDatasetReason
                                        showDisabledUseReason = true
                                    }
                                } else {
                                    disabledUseReason = disabledUseDatasetReason
                                    showDisabledUseReason = true
                                }
                            } label: {
                                Text(LocalizedStringKey("Use Dataset"))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(!isReady || disabledForSLM)
                        }
                        
                        if isCurrentlyIndexing, let s = datasetManager.processingStatus[dataset.datasetID] {
                            VStack(spacing: 4) {
                                ProgressView(value: s.progress)
                                    .tint(.blue)
                                let eta: String = {
                                    if let e = s.etaSeconds, e > 0 {
                                        return String(format: "~%dm %02ds", Int(e)/60, Int(e)%60)
                                    } else { return "…" }
                                }()
                                Text(String.localizedStringWithFormat(String(localized: "Indexing: %d%% · %@"), Int(s.progress * 100), eta))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)
                        }
                        
                        Button(role: .destructive) {
                            try? datasetManager.delete(dataset)
                            close()
                        } label: {
                            Text(LocalizedStringKey("Delete Dataset"))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 30)
                }
            }
            .background(windowBackgroundColor) // Use window background
            .navigationTitle(dataset.name)
            #if !os(macOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(LocalizedStringKey("Close")) { close() } }
            }
            #endif
            .alert(LocalizedStringKey("Unavailable"), isPresented: $showDisabledUseReason) {
                Button(LocalizedStringKey("OK"), role: .cancel) { disabledUseReason = "" }
            } message: {
                Text(disabledUseReason.isEmpty ? disabledUseDatasetReason : disabledUseReason)
            }
            .task {
                loadFiles()
                await computeCompressedSize()
            }
        }
    }

    // MARK: - Subviews
    
    private struct InfoRow: View {
        let label: String
        let value: String
        
        var body: some View {
            HStack {
                Text(label)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .bold()
            }
        }
    }
    
    @ViewBuilder
    private func processingView(status s: DatasetProcessingStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Stage indicator
            HStack(spacing: 12) {
                ForEach(Array([DatasetProcessingStage.extracting, .compressing, .embedding].enumerated()), id: \.offset) { index, stage in
                    VStack(spacing: 4) {
                        Circle()
                            .fill(currentStageColor(stage, current: s.stage))
                            .frame(width: 16, height: 16)
                        Text(stageLabel(stage))
                            .font(.caption2)
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
                        Text(LocalizedStringKey("Embedding"))
                            .bold()
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                } else if s.stage == .failed {
                    Text(s.message ?? stageLabel(s.stage))
                        .foregroundStyle(.red)
                } else {
                    Text(stageLabel(s.stage))
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
                        Text(LocalizedStringKey("Confirm and Start Embedding"))
                    }
                    .buttonStyle(.borderedProminent)
                    .confirmationDialog(Text(LocalizedStringKey("Proceed on battery power?")), isPresented: $showConfirmOnBatteryConfirm, titleVisibility: .visible) {
                        Button(LocalizedStringKey("Proceed")) {
                            Task {
                                await chatVM.unload()
                                datasetManager.startEmbeddingForID(dataset.datasetID)
                            }
                        }
                        Button(LocalizedStringKey("Cancel"), role: .cancel) {}
                    } message: {
                        Text(LocalizedStringKey("Embedding is resource intensive. For best performance, plug in your phone. Do you want to proceed on battery?"))
                    }
                    Text(LocalizedStringKey("For best performance, please plug in your phone until this completes."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Button(LocalizedStringKey("Stop"), role: .destructive) {
                datasetManager.cancelProcessingForID(dataset.datasetID)
            }
            .buttonStyle(.bordered)
        }
    }
    
    @ViewBuilder
    private func readyView() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if warmingUpEmbed {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        let isDownloading = embedStatusPhase == .downloading
                        Image(systemName: isDownloading ? "arrow.down.circle.fill" : "cpu")
                            .foregroundColor(.blue)
                            .applySymbolPulse(isDownloading: isDownloading)
                        Text(LocalizedStringKey("Preparing Embedding Model"))
                            .font(.headline)
                    }
                    
                    ProgressView(value: embedProgress)
                        .tint(.blue)
                    
                    if !embedStatusMessage.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(embedStatusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            if embedStatusPhase == .downloading {
                                HStack {
                                    Image(systemName: "info.circle")
                                        .font(.caption2)
                                    Text(LocalizedStringKey("First-time download from HuggingFace"))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
            } else if embedReady && modelManager.activeDataset?.datasetID == dataset.datasetID {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .applySymbolBounce(value: embedReady)
                    Text(LocalizedStringKey("Embedding Model Ready"))
                        .font(.headline)
                        .foregroundColor(.green)
                }
            } else {
                // Show ready indicator only if dataset is fully indexed
                let isReady = dataset.isIndexed || (datasetManager.processingStatus[dataset.datasetID]?.stage == .completed)
                if isReady {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(LocalizedStringKey("Ready for Use"))
                            .font(.headline)
                            .foregroundColor(.green)
                    }
                }
            }
            
            if !warmingUpEmbed {
                Text(LocalizedStringKey("RAG embeds normalized paragraphs from your PDFs and EPUBs. On each question, the most relevant chunks are retrieved and added to the prompt. Images are ignored."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // Only show manual start when not yet indexed/embedded and no active processing
            let isReady = dataset.isIndexed || (datasetManager.processingStatus[dataset.datasetID]?.stage == .completed)
            if !isReady {
                Button(LocalizedStringKey("Start Embedding Process")) {
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
                .confirmationDialog(Text(LocalizedStringKey("Proceed on battery power?")), isPresented: $showStartOnBatteryConfirm, titleVisibility: .visible) {
                    Button(LocalizedStringKey("Proceed")) {
                        Task {
                            await chatVM.unload()
                            datasetManager.startEmbeddingForID(dataset.datasetID)
                        }
                    }
                    Button(LocalizedStringKey("Cancel"), role: .cancel) {}
                } message: {
                    Text(LocalizedStringKey("Embedding is resource intensive. For best performance, plug in your phone. Do you want to proceed on battery?"))
                }
            }
        }
    }

    @MainActor
    private func prepareEmbeddingsAndIndex() async {
        let liveDataset = datasetManager.datasets.first(where: { $0.datasetID == dataset.datasetID }) ?? dataset
        let status = datasetManager.processingStatus[dataset.datasetID]
        let hasVectors = FileManager.default.fileExists(atPath: liveDataset.url.appendingPathComponent("vectors.json").path)
        let alreadyReady = liveDataset.isIndexed || status?.stage == .completed || hasVectors
        if alreadyReady {
            embedStatusMessage = ""
            embedStatusPhase = .idle
            embedProgress = 1.0
            embedReady = true
            warmingUpEmbed = false
            return
        }

        embedStatusPhase = .checking
        embedStatusMessage = String(localized: "Checking embedding model…")
        embedProgress = 0.05
        // Ensure dirs only (no network)
        await EmbeddingModel.shared.ensureModel()
        if !(await EmbeddingModel.shared.isModelAvailable()) {
            embedStatusPhase = .downloading
            embedStatusMessage = String(localized: "Downloading embedding model…")
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
                embedStatusPhase = .failed
                embedStatusMessage = String(format: String(localized: "Failed: %@"), msg)
                warmingUpEmbed = false
                return
            case .ready:
                embedProgress = 0.7
                break
            default:
                break
            }
        }
        embedStatusPhase = .loading
        embedStatusMessage = String(localized: "Loading model…")
        embedProgress = 0.7
        await EmbeddingModel.shared.warmUp()
        let ready = await EmbeddingModel.shared.isReady()
        if ready {
            embedStatusPhase = .indexing
            embedStatusMessage = String(localized: "Indexing dataset…")
            embedProgress = 0.85
            let alreadyCompleted = status?.stage == .completed || liveDataset.isIndexed || hasVectors
            if !alreadyCompleted && chatVM.modelLoaded {
                await chatVM.unload()
            }
            datasetManager.ensureIndexedForID(dataset.datasetID)
            embedReady = true
            embedProgress = 1.0
        } else {
            embedStatusPhase = .failed
            embedStatusMessage = String(localized: "Failed to initialize")
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            warmingUpEmbed = false
            embedStatusMessage = ""
            embedStatusPhase = .idle
        }
    }

    private func loadFiles() {
        let fm = FileManager.default
        var items: [(name: String, size: String)] = []
        if let enumerator = fm.enumerator(at: dataset.url, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) {
            while let url = enumerator.nextObject() as? URL {
                let base = url.lastPathComponent
                if ["vectors.json", "extracted.txt", "extracted.compact.txt", "title.txt"].contains(base) { continue }
                if let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                   values.isRegularFile == true {
                    let relative = url.path.replacingOccurrences(of: dataset.url.path + "/", with: "")
                    let sizeStr = localizedFileSizeString(bytes: Int64(values.fileSize ?? 0), locale: locale)
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
            let formatter = NumberFormatter()
            formatter.locale = locale
            formatter.numberStyle = .decimal
            tokenEstimate = formatter.string(from: NSNumber(value: tokens)) ?? "\(tokens)"
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
            let formatted = localizedFileSizeString(bytes: bytes.int64Value, locale: locale)
            await MainActor.run {
                compressedMB = String.localizedStringWithFormat(String(localized: "Approx. %@", locale: locale), formatted)
            }
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

// MARK: - Symbol effect compatibility helpers (iOS 17+ / macOS 14+ / visionOS 1+)
private extension View {
    @ViewBuilder
    func applySymbolPulse(isDownloading: Bool) -> some View {
        // Gate usage to platforms/versions that support `symbolEffect`.
        if #available(iOS 17.0, macOS 14.0, visionOS 1.0, *) {
            self.symbolEffect(isDownloading ? .pulse.byLayer : .pulse)
        } else {
            self
        }
    }

    @ViewBuilder
    func applySymbolBounce<Value: Equatable>(value: Value) -> some View {
        if #available(iOS 17.0, macOS 14.0, visionOS 1.0, *) {
            self.symbolEffect(.bounce, value: value)
        } else {
            self
        }
    }
}

private enum EmbedStatusPhase {
    case idle
    case checking
    case downloading
    case loading
    case indexing
    case failed
}

private func stageLabel(_ s: DatasetProcessingStage) -> String {
    switch s {
    case .extracting: return "Extracting".localized
    case .compressing: return "Compressing".localized
    case .embedding: return "Embedding".localized
    case .completed: return "Ready".localized
    case .failed: return "Failed".localized
    }
}

private extension LocalDatasetDetailView {
    var slmUseDatasetReason: String { "SLM models aren't yet RAG compatible.".localized }
    // Remote models are supported for RAG; reason removed.

    var disabledUseDatasetReason: String {
        if datasetManager.indexingDatasetID == dataset.datasetID {
            return "Dataset is currently indexing. You can use it when indexing completes.".localized
        }
        return "This dataset isn’t ready yet. Start the embedding process above first.".localized
    }

    var cardBackgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }

    var windowBackgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }

    func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}

@MainActor
private func isPluggedIn() -> Bool {
#if canImport(UIKit)
    UIDevice.current.isBatteryMonitoringEnabled = true
    let state = UIDevice.current.batteryState
    return state == .charging || state == .full
#else
    return true
#endif
}
