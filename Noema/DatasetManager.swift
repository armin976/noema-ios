// DatasetManager.swift
import Foundation
import SwiftUI
// Live Activities removed

@MainActor
final class DatasetManager: ObservableObject {
    @Published private(set) var datasets: [LocalDataset] = []
    @AppStorage("selectedDatasetID") private var selectedDatasetID: String = ""
    @AppStorage("embeddedDatasetIDs") private var embeddedDatasetIDsRaw: String = ""
    @Published var indexingDatasetID: String?
    struct AlertItem: Identifiable { let id = UUID(); let message: String }
    @Published var embedAlert: AlertItem?
    @Published var processingStatus: [String: DatasetProcessingStatus] = [:]
    @AppStorage("indexingDatasetIDPersisted") private var persistedIndexingDatasetID: String = ""

    /// Download controller used to fetch the embedding model when missing.
    weak var downloadController: DownloadController?
    private var indexingTasks: [String: Task<Void, Never>] = [:]
    private var startupAutoIndexDone = false
    // Throttle and coalesce frequent status updates to avoid UI flicker
    private var lastStatusByID: [String: DatasetProcessingStatus] = [:]
    private var lastStatusUpdateAt: [String: Date] = [:]

    /// Updates the processing status for a dataset with coalescing to minimize UI re-renders.
    /// - Uses a minimum interval between updates and only publishes when values meaningfully change.
    private func updateProcessingStatus(_ status: DatasetProcessingStatus, for id: String) {
        let now = Date()
        let last = lastStatusByID[id]
        let lastTime = lastStatusUpdateAt[id] ?? .distantPast
        let minInterval: TimeInterval = 0.2 // 5 fps update cadence is sufficient for progress UI

        // Only publish if stage changed or progress advanced by at least 1% or enough time elapsed
        let stageChanged = last?.stage != status.stage
        let progressDelta = Swift.abs((last?.progress ?? -1.0) - status.progress)
        let timeElapsed = now.timeIntervalSince(lastTime)
        if stageChanged || progressDelta >= 0.01 || timeElapsed >= minInterval {
            processingStatus[id] = status
            lastStatusByID[id] = status
            lastStatusUpdateAt[id] = now
            if status.stage == .failed, status.message == "Stopped" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.processingStatus[id] = nil
                    self?.lastStatusByID[id] = nil
                    self?.lastStatusUpdateAt[id] = nil
                }
            }
        }
    }

    init() {
        // Clear any previously selected dataset on app startup
        // User must explicitly select a dataset each session
        selectedDatasetID = ""
        reloadFromDisk()
        // Run a single auto-index scan on first app launch only
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            if !self.startupAutoIndexDone {
                self.autoIndexNewDatasets()
                self.startupAutoIndexDone = true
            }
        }
        // Restore any persisted indexing dataset ID so we can resume processing if app was closed.
        if !persistedIndexingDatasetID.isEmpty {
            // Automatically resume or restart the indexing pipeline on launch.
            ensureIndexedForID(persistedIndexingDatasetID)
        }
    }

    func bind(downloadController: DownloadController) {
        self.downloadController = downloadController
    }

    func reloadFromDisk() {
        var url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url.appendPathComponent("LocalLLMDatasets", isDirectory: true)
        let fm = FileManager.default
        var found: [LocalDataset] = []
        if let owners = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles) {
            for owner in owners {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: owner.path, isDirectory: &isDir), isDir.boolValue {
                    if let datasets = try? fm.contentsOfDirectory(at: owner, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles) {
                        for dir in datasets {
                            var isDir2: ObjCBool = false
                            if fm.fileExists(atPath: dir.path, isDirectory: &isDir2), isDir2.boolValue {
                                let size = (try? directorySize(at: dir)) ?? 0
                                // Convert bytes to megabytes for display
                                let sizeMB = Double(size) / 1_048_576.0
                                let attrs = try? fm.attributesOfItem(atPath: dir.path)
                                let created = attrs?[.creationDate] as? Date ?? Date()
                                let id = owner.lastPathComponent + "/" + dir.lastPathComponent
                                // Consider dataset fully indexed only when embeddings are present
                                let indexed = fm.fileExists(atPath: dir.appendingPathComponent("vectors.json").path)
                                let sourceName: String = {
                                    let ownerName = owner.lastPathComponent
                                    if ownerName == "OTL" { return "Open Textbook Library" }
                                    if ownerName == "Imported" { return "Imported" }
                                    return "Hugging Face"
                                }()
                                // Prefer a human-readable title persisted during download when available
                                let displayName: String = {
                                    let titleURL = dir.appendingPathComponent("title.txt")
                                    if let title = try? String(contentsOf: titleURL).trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                                        return title
                                    }
                                    return dir.lastPathComponent
                                }()
                                var ds = LocalDataset(datasetID: id,
                                                      name: displayName,
                                                      url: dir,
                                                      sizeMB: sizeMB,
                                                      source: sourceName,
                                                      downloadDate: created,
                                                      lastUsedDate: nil,
                                                      isSelected: selectedDatasetID == id,
                                                      isIndexed: indexed)
                                found.append(ds)
                            }
                        }
                    }
                }
            }
        }
        datasets = found
        // Preserve any in-flight processing status to avoid UI flicker when refreshing from disk.
        // Only set to completed if indexed on disk; only clear entries for datasets no longer present.
        let embedded = Set(embeddedDatasetIDsRaw.split(separator: ",").map(String.init))
        var newStatus: [String: DatasetProcessingStatus] = [:]
        for ds in found {
            if let existing = processingStatus[ds.datasetID], existing.stage != .completed {
                // Keep ongoing progress; it will be updated by the pipeline callback
                newStatus[ds.datasetID] = existing
            } else if ds.isIndexed {
                if !embedded.contains(ds.datasetID) { markEmbedded(ds.datasetID) }
                newStatus[ds.datasetID] = DatasetProcessingStatus(stage: .completed, progress: 1.0, message: "Ready", etaSeconds: 0)
            } else {
                // Not indexed and no existing progress; omit status
            }
        }
        processingStatus = newStatus
        // Keep lastStatusByID consistent with the currently visible statuses
        lastStatusByID = newStatus

        // If a dataset finished indexing (or was removed) while the app was off,
        // clear any stale indexing flags so UI elements like the chat input box
        // are re-enabled.
        if let current = indexingDatasetID {
            let stillIndexing = datasets.contains { $0.datasetID == current && !$0.isIndexed }
            if !stillIndexing {
                indexingDatasetID = nil
                persistedIndexingDatasetID = ""
            }
        }

        // Do not auto-index here; it should only happen once at startup
    }

    private func directorySize(at url: URL) throws -> Int64 {
        let fm = FileManager.default
        let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])
        var total: Int64 = 0
        while let next = enumerator?.nextObject() as? URL {
            let values = try next.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values.isRegularFile == true {
                total += Int64(values.fileSize ?? 0)
            }
        }
        return total
    }

    func delete(_ ds: LocalDataset) throws {
        cancelProcessingForID(ds.datasetID)
        // Remove on-disk dataset directory first
        try FileManager.default.removeItem(at: ds.url)
        // Purge embeddings cache and vectors file for this dataset
        Task { await DatasetRetriever.shared.purge(datasetID: ds.datasetID) }
        if selectedDatasetID == ds.datasetID { selectedDatasetID = "" }
        var set = Set(embeddedDatasetIDsRaw.split(separator: ",").map(String.init))
        set.remove(ds.datasetID)
        embeddedDatasetIDsRaw = set.joined(separator: ",")
        processingStatus[ds.datasetID] = nil
        reloadFromDisk()
    }

    func cancelProcessingForID(_ id: String) {
        Task { await logger.log("[DatasetManager] Cancelling processing for: \(id)") }
        indexingTasks[id]?.cancel()
        indexingTasks[id] = nil
        if indexingDatasetID == id { indexingDatasetID = nil }
        if persistedIndexingDatasetID == id { persistedIndexingDatasetID = "" }
        // Keep the last known status so the pipeline can publish a final "Stopped" state.
        // It will be cleared after the final update is processed.
    }

    func select(_ ds: LocalDataset?) {
        selectedDatasetID = ds?.datasetID ?? ""
        // Reflect dataset active/idle state in UserDefaults keys used by WebToolGate
        // so backends that are not on the main actor can gate tool usage reliably.
        let d = UserDefaults.standard
        if let id = ds?.datasetID, !id.isEmpty {
            d.set(id, forKey: "selectedDatasetID")
        } else {
            d.set("", forKey: "selectedDatasetID")
        }
        reloadFromDisk()
        // Do not auto-download/embedder or auto-index here; user must trigger manually in UI.
    }

    var selectedDataset: LocalDataset? {
        datasets.first { $0.datasetID == selectedDatasetID }
    }

    func ensureIndexedForID(_ id: String) {
        Task { await logger.log("[DatasetManager] ensureIndexedForID called for: \(id)") }
        if let ds = datasets.first(where: { $0.datasetID == id }) {
            ensureIndexed(ds)
        } else {
            Task { await logger.log("[DatasetManager] ❌ Dataset not found for ID: \(id)") }
        }
    }
    
    /// Auto-index newly downloaded datasets
    func autoIndexNewDatasets() {
        Task { await logger.log("[DatasetManager] Checking for datasets to auto-index...") }
        for ds in datasets {
            // Skip if the dataset is already finished processing according to our in-memory status, even if the
            // vectors.json file hasn’t been observed on disk yet. This prevents accidentally re-queuing the
            // embedding pipeline due to subtle file-system timing issues.
            let alreadyCompleted = processingStatus[ds.datasetID]?.stage == .completed
            if !ds.isIndexed && !alreadyCompleted && indexingDatasetID != ds.datasetID {
                Task { await logger.log("[DatasetManager] Auto-indexing new dataset: \(ds.datasetID)") }
                ensureIndexed(ds)
                break // Only index one at a time
            }
        }
    }

    private func ensureIndexed(_ ds: LocalDataset) {
        guard !ds.isIndexed else {
            Task { await logger.log("[DatasetManager] ensureIndexed called but dataset already indexed: \(ds.datasetID)") }
            // Clear any stale indexing state so the UI isn't locked out
            if indexingDatasetID == ds.datasetID {
                indexingDatasetID = nil
            }
            if persistedIndexingDatasetID == ds.datasetID {
                persistedIndexingDatasetID = ""
            }
            return
        }
        if indexingTasks[ds.datasetID] != nil { return }

        Task { await logger.log("[DatasetManager] Starting indexing for dataset: \(ds.datasetID)") }
        indexingDatasetID = ds.datasetID
        persistedIndexingDatasetID = ds.datasetID

        let t = Task {
            // No download here; strict on-demand handled by Use Dataset flow
            Task { await logger.log("[DatasetManager] Ensuring embedding model for: \(ds.datasetID)") }
            // Ensure model directory and download model if missing so embedding can proceed
            await EmbeddingModel.shared.ensureModel()
            if !(await EmbeddingModel.shared.isModelAvailable()) {
                await MainActor.run {
                    self.processingStatus[ds.datasetID] = DatasetProcessingStatus(stage: .embedding, progress: 0.0, message: "Downloading embedding model…", etaSeconds: nil)
                }
                let installTask = Task { @MainActor in
                    let installer = EmbedModelInstaller()
                    await installer.installIfNeeded()
                }
                _ = await installTask.value
            }
            
            Task { await logger.log("[DatasetManager] Starting DatasetRetriever.prepare for: \(ds.datasetID)") }
            await DatasetRetriever.shared.prepare(dataset: ds, pauseBeforeEmbedding: true) { status in
                Task { @MainActor in
                    self.updateProcessingStatus(status, for: ds.datasetID)
                }
                // Stream logs to file on each update for transparency
                let pct = Int(status.progress * 100)
                let stage = self.stageName(status.stage)
                let etaStr: String = {
                    if let e = status.etaSeconds, e > 0 { return String(format: "~%dm %02ds", Int(e)/60, Int(e)%60) }
                    return "…"
                }()
                Task { await logger.log("[RAG][UI] \(ds.datasetID) \(stage) \(pct)% ETA \(etaStr) – \(status.message ?? "")") }
            }
            
            await MainActor.run {
                // Only clear when actually completed; if paused awaiting confirmation, keep visible
                let stage = self.processingStatus[ds.datasetID]?.stage
                if stage == .completed {
                    Task { await logger.log("[DatasetManager] Indexing completed for: \(ds.datasetID)") }
                    self.indexingDatasetID = nil
                    self.persistedIndexingDatasetID = ""
                    self.reloadFromDisk()
                }
                self.indexingTasks[ds.datasetID] = nil
            }
        }
        indexingTasks[ds.datasetID] = t
    }

    /// Explicit user-triggered embedding: proceed through embedding automatically (no pause gate)
    func startEmbeddingForID(_ id: String) {
        Task { await logger.log("[DatasetManager] startEmbeddingForID called for: \(id)") }
        guard let ds = datasets.first(where: { $0.datasetID == id }) else {
            Task { await logger.log("[DatasetManager] ❌ Dataset not found for ID: \(id)") }
            return
        }
        if ds.isIndexed {
            Task { await logger.log("[DatasetManager] startEmbeddingForID: already indexed: \(ds.datasetID)") }
            return
        }
        if indexingTasks[ds.datasetID] != nil { return }
        indexingDatasetID = ds.datasetID
        persistedIndexingDatasetID = ds.datasetID
        let t = Task {
            // Ensure model present/installed
            await EmbeddingModel.shared.ensureModel()
            if !(await EmbeddingModel.shared.isModelAvailable()) {
                await MainActor.run {
                    self.updateProcessingStatus(DatasetProcessingStatus(stage: .embedding, progress: 0.0, message: "Downloading embedding model…", etaSeconds: nil), for: ds.datasetID)
                }
                let installer = EmbedModelInstaller()
                // Stream installer progress into the dataset status so the UI reflects download progress
                let progressTask = Task { @MainActor in
                    while !Task.isCancelled {
                        switch installer.state {
                        case .downloading, .verifying, .installing:
                            // Map installer progress directly to the status progress for clear feedback
                            let p = max(0.0, min(1.0, installer.progress))
                            self.updateProcessingStatus(DatasetProcessingStatus(stage: .embedding, progress: p, message: "Downloading embedding model…", etaSeconds: nil), for: ds.datasetID)
                        default:
                            break
                        }
                        try? await Task.sleep(nanoseconds: 150_000_000)
                    }
                }
                await installer.installIfNeeded()
                progressTask.cancel()
                // Handle download failure explicitly and stop indexing so the user can retry
                switch installer.state {
                case .failed(let msg):
                    await MainActor.run {
                        self.processingStatus[ds.datasetID] = DatasetProcessingStatus(stage: .failed, progress: 0.0, message: "Failed to download embedding model: \(msg)", etaSeconds: nil)
                        self.indexingDatasetID = nil
                        self.persistedIndexingDatasetID = ""
                    }
                    return
                default:
                    break
                }
            }

            await DatasetRetriever.shared.prepare(dataset: ds, pauseBeforeEmbedding: false) { status in
                Task { @MainActor in
                    self.updateProcessingStatus(status, for: ds.datasetID)
                }
                let pct = Int(status.progress * 100)
                let stage = self.stageName(status.stage)
                let etaStr: String = {
                    if let e = status.etaSeconds, e > 0 { return String(format: "~%dm %02ds", Int(e)/60, Int(e)%60) }
                    return "…"
                }()
                Task { await logger.log("[RAG][UI] \(ds.datasetID) \(stage) \(pct)% ETA \(etaStr) – \(status.message ?? "")") }
            }

            await MainActor.run {
                let stage = self.processingStatus[ds.datasetID]?.stage
                if stage == .completed {
                    self.indexingDatasetID = nil
                    self.persistedIndexingDatasetID = ""
                    self.reloadFromDisk()
                }
                self.indexingTasks[ds.datasetID] = nil
            }
        }
        indexingTasks[ds.datasetID] = t
    }

    // Public API: background start indexing after a download completes
    public func startIndexing(dataset: LocalDataset) {
        if indexingTasks[dataset.datasetID] != nil { return }
        let t = Task(priority: .background) { [weak self] in
            guard let self else { return }
            await logger.log("[DatasetManager] Starting background indexing for downloaded dataset: \(dataset.datasetID)")
            await MainActor.run {
                self.indexingDatasetID = dataset.datasetID
                self.persistedIndexingDatasetID = dataset.datasetID
            }
            // Ensure model folder and download model if missing
            await EmbeddingModel.shared.ensureModel()
            if !(await EmbeddingModel.shared.isModelAvailable()) {
                await MainActor.run {
                    self.processingStatus[dataset.datasetID] = DatasetProcessingStatus(stage: .embedding, progress: 0.0, message: "Downloading embedding model…", etaSeconds: nil)
                }
                let installTask = Task { @MainActor in
                    let installer = EmbedModelInstaller()
                    await installer.installIfNeeded()
                }
                _ = await installTask.value
            }
            await DatasetRetriever.shared.prepare(dataset: dataset, pauseBeforeEmbedding: true) { status in
                Task { @MainActor in self.updateProcessingStatus(status, for: dataset.datasetID) }
            }
            await MainActor.run {
                self.indexingTasks[dataset.datasetID] = nil
                self.persistedIndexingDatasetID = ""
            }
        }
        indexingTasks[dataset.datasetID] = t
    }

    private func stageName(_ s: DatasetProcessingStage) -> String {
        switch s {
        case .extracting: return "Extracting"
        case .compressing: return "Compressing"
        case .embedding: return "Embedding / Warming Up"
        case .completed: return "Ready"
        case .failed: return "Failed"
        }
    }
    
    private func markEmbedded(_ id: String) {
        var set = Set(embeddedDatasetIDsRaw.split(separator: ",").map(String.init))
        set.insert(id)
        embeddedDatasetIDsRaw = set.joined(separator: ",")
    }

    // MARK: - Import from Files

    /// Import local documents (PDF/EPUB/TXT) from Files into a new dataset under `Documents/LocalLLMDatasets/Imported/<name>`.
    /// - Returns: The created `LocalDataset` if successful, otherwise nil.
    @discardableResult
    func importDocuments(from urls: [URL], suggestedName: String?) async -> LocalDataset? {
        // Filter allowed extensions
        let allowedExts: Set<String> = ["pdf", "epub", "txt"]
        let picked = urls.filter { allowedExts.contains($0.pathExtension.lowercased()) }
        guard !picked.isEmpty else { return nil }

        // Pick a dataset name
        let defaultName: String = {
            if let s = suggestedName, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return s }
            // Prefer first PDF/EPUB name; fallback to first file name
            if let u = picked.first(where: { ["pdf", "epub"].contains($0.pathExtension.lowercased()) }) ?? picked.first {
                let base = u.deletingPathExtension().lastPathComponent
                return DatasetManager.humanizeFileName(base)
            }
            return "Imported Dataset"
        }()

        // Build destination directory
        let (datasetID, destDir) = DatasetManager.makeImportedDatasetDir(named: defaultName)

        // Ensure folders
        do {
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        // Copy picked files
        for url in picked {
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let dest = destDir.appendingPathComponent(url.lastPathComponent)
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: url, to: dest)
            } catch {
                // Best-effort: continue copying other files
            }
        }

        // Persist human-readable title for display
        let titleURL = destDir.appendingPathComponent("title.txt")
        try? defaultName.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8)?.write(to: titleURL)

        // Refresh in-memory list and return the created dataset
        reloadFromDisk()
        if let ds = datasets.first(where: { $0.datasetID == datasetID }) {
            return ds
        }
        return nil
    }

    // MARK: - Helpers
    private static func makeImportedDatasetDir(named name: String) -> (String, URL) {
        var base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        base.appendPathComponent("LocalLLMDatasets", isDirectory: true)
        base.appendPathComponent("Imported", isDirectory: true)

        let slug = slugify(name)
        var dir = base.appendingPathComponent(slug, isDirectory: true)
        var finalSlug = slug
        var suffix = 2
        while FileManager.default.fileExists(atPath: dir.path) {
            finalSlug = slug + "-" + String(suffix)
            dir = base.appendingPathComponent(finalSlug, isDirectory: true)
            suffix += 1
        }
        let id = "Imported/" + finalSlug
        return (id, dir)
    }

    private static func slugify(_ s: String) -> String {
        let invalid = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ ")).inverted
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.replacingOccurrences(of: "[\\s_]+", with: "-", options: .regularExpression)
        t = t.components(separatedBy: invalid).joined(separator: "")
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if t.isEmpty { t = "dataset" }
        return t.lowercased()
    }

    private static func humanizeFileName(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "[_-]+", with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

struct DatasetRow: View {
    let dataset: LocalDataset
    let indexing: Bool
    @EnvironmentObject var datasetManager: DatasetManager
    @EnvironmentObject var modelManager: AppModelManager
    var body: some View {
        HStack {
            Image(systemName: "doc.richtext")
            VStack(alignment: .leading) {
                Text(dataset.name).font(.headline)
                Text(dataset.source).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            statusView
        }
    }

    @ViewBuilder
    private var statusView: some View {
        let status = datasetManager.processingStatus[dataset.datasetID]
        let isProcessing = indexing || (status != nil && status?.stage != .completed)
        VStack(alignment: .trailing, spacing: 4) {
            Text(String(format: "%.0f MB", dataset.sizeMB))
                .font(.footnote).foregroundStyle(.secondary)
            if isProcessing, let s = status {
                ZStack {
                    Circle().stroke(Color.gray.opacity(0.3), lineWidth: 3).frame(width: 22, height: 22)
                    Circle()
                        .trim(from: 0, to: CGFloat(max(0, min(1, s.progress))))
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 22, height: 22)
                    Text("\(Int(s.progress * 100))")
                        .font(.system(size: 9)).monospacedDigit()
                }
                Text(stageLabel(s.stage))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let m = s.message, !m.isEmpty {
                    Text(m)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if modelManager.activeDataset?.datasetID == dataset.datasetID {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private func stageLabel(_ s: DatasetProcessingStage) -> String {
        switch s {
        case .extracting: return "Extracting"
        case .compressing: return "Compressing"
        case .embedding: return "Embedding / Warming Up"
        case .completed: return "Ready"
        case .failed: return "Failed"
        }
    }
}
