// DownloadController.swift
#if canImport(UIKit) || os(macOS)
import Foundation
import SwiftUI
import Network

@MainActor
final class DownloadController: ObservableObject {
	// Smoothing constant for download speed (EMA). Lower = steadier.
    private let speedEMAAlpha: Double = 0.30
	// Consider speeds stale if no update arrives within this window
	private let speedStaleAfter: TimeInterval = 1.25
	// Clamp unrealistically large instantaneous spikes (in B/s)
    // Upper bound for instantaneous samples to avoid UI spikes; set high enough to not mask real speeds
    private let maxInstantaneousSpeed: Double = 512 * 1024 * 1024 // ~512 MB/s

    // Track last time we updated a speed sample per item category
    private var lastModelSpeedSampleAt: [String: Date] = [:]
    private var lastLeapSpeedSampleAt: [String: Date] = [:]
    private var lastDatasetSpeedSampleAt: [String: Date] = [:]
    private var speedCoastTask: Task<Void, Never>? = nil
    // Per-main-model speed sampling state (computed from fraction * expected)
    private var lastMainSpeedSampleAt: [String: Date] = [:]
    private var lastMainBytesSample: [String: Int64] = [:]
    // Per-mmproj speed sampling state (computed from delegate byte deltas)
    private var lastMMProjSpeedSampleAt: [String: Date] = [:]
    private var lastMMProjBytesSample: [String: Int64] = [:]
    // Track the last expected size we surfaced per download kind to avoid log spam
    private var loggedMainExpected: [String: Int64] = [:]
    private var loggedMMProjExpected: [String: Int64] = [:]
    private var loggedDatasetExpected: [String: Int64] = [:]
    private var loggedLeapExpected: [String: Int64] = [:]
    private var loggedEmbedExpected: [String: Int64] = [:]

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB]
        return f
    }()
	struct Item: Identifiable, Equatable {
		let detail: ModelDetails
		let quant: QuantInfo
        var progress: Double = 0
        var speed: Double = 0
        // Track per-transfer instantaneous speeds (EMA-smoothed)
        var mainSpeed: Double = 0
        var mmprojSpeed: Double = 0
		var completed = false
		var error: DownloadError? = nil
		var retryCount: Int = 0
		// Track per-part progress for combined progress computation
        var mainProgress: Double = 0
        var mmprojProgress: Double = 0
        var mmprojSize: Int64 = 0
        // Remember projector filename so on-disk size probes can find the right file after completion.
        var mmprojFilename: String? = nil
        // Absolute byte accounting for more accurate combined progress
        var mainExpectedBytes: Int64 = 0
        var mainBytesWritten: Int64 = 0
        var mmprojBytesWritten: Int64 = 0
		// Destination of an in-flight mmproj background download (if any); used to pause/cancel correctly
		var mmprojDestination: URL? = nil

		var id: String { "\(detail.id)-\(quant.label)" }
		
		var isRetryable: Bool {
			error?.isRetryable == true
		}
	}
	
	enum DownloadError: Equatable {
		case networkError(String)
		case permanentError(String)
		
		var isRetryable: Bool {
			switch self {
			case .networkError: return true
			case .permanentError: return false
			}
		}
		
		var localizedDescription: String {
			switch self {
			case .networkError(let message): return message
			case .permanentError(let message): return message
			}
		}
	}

	struct LeapItem: Identifiable, Equatable {
		let entry: LeapCatalogEntry
		var progress: Double = 0
		var speed: Double = 0
		/// Expected total bytes for this SLM bundle. Filled when download starts or on first progress event.
		var expectedBytes: Int64 = 0
		var completed = false
		var verifying = false
		/// Number of consecutive retries for backoff
		var retryCount: Int = 0

		var id: String { entry.slug }
	}

        struct DatasetItem: Identifiable, Equatable {
                let detail: DatasetDetails
                var progress: Double = 0
                var speed: Double = 0
                /// Expected total bytes for this dataset download (if known)
                var expectedBytes: Int64 = 0
                /// Bytes downloaded so far for this dataset
                var downloadedBytes: Int64 = 0
                var completed = false
                var error: DownloadError? = nil

                var id: String { detail.id }
        }

	struct EmbeddingItem: Identifiable, Equatable {
		let repoID: String
		var progress: Double = 0
		var speed: Double = 0
		var completed = false
		var error: DownloadError? = nil
        /// Expected total bytes for this embedding model download (if known)
        var expectedBytes: Int64 = 0

		var id: String { repoID }
	}
	
	/// Active downloads keyed by "<modelID>-<quantLabel>"
	@Published private(set) var items: [Item] = []
	@Published private(set) var leapItems: [LeapItem] = []
	@Published private(set) var datasetItems: [DatasetItem] = []
	@Published private(set) var embeddingItems: [EmbeddingItem] = []
	@Published var showOverlay = false
	@Published var showPopup = false
	/// When set, ExploreView should present the associated details
	@Published var navigateToDetail: ModelDetails?

	private let manager = ModelDownloadManager()
	private var tasks: [String: Task<Void, Never>] = [:]
	// Track pause state per download id
	@Published private(set) var paused: Set<String> = []
	// Explicit module qualification avoids ambiguity with similarly named types
#if os(macOS) && !canImport(UIKit)
	private weak var modelManager: AnyObject?
#else
	private weak var modelManager: AppModelManager?
#endif
	private weak var datasetManager: DatasetManager?

	init() {
		// Periodically zero speeds that have gone stale (e.g., pause, network stall)
        speedCoastTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    let now = Date()
            		// Models
            		for i in items.indices {
            			let id = items[i].id
            			if let t = lastModelSpeedSampleAt[id], now.timeIntervalSince(t) > speedStaleAfter || paused.contains(id) {
            				items[i].speed = 0
                            items[i].mainSpeed = 0
                            items[i].mmprojSpeed = 0
            			}
            		}
					// Leaps
					for i in leapItems.indices {
						let id = leapItems[i].id
						if let t = lastLeapSpeedSampleAt[id], now.timeIntervalSince(t) > speedStaleAfter {
							leapItems[i].speed = 0
						}
					}
					// Datasets
            		for i in datasetItems.indices {
            			let id = datasetItems[i].id
            			if let t = lastDatasetSpeedSampleAt[id], now.timeIntervalSince(t) > speedStaleAfter {
            				datasetItems[i].speed = 0
            			}
            		}
                    // If a download reached 100% but never fired .finished (e.g., delegate lost),
                    // finalize it when the on-disk files are present.
                    autoFinalizeCompletedOnDisk()
                }
            }
        }

		// Observe background download completion notifications so we can
		// finalize installs even if the original async continuation was lost.
        NotificationCenter.default.addObserver(forName: .backgroundDownloadCompleted, object: nil, queue: .main) { [weak self] note in
            let destinationURL = note.userInfo?["destinationURL"] as? URL
            let errorMessage: String? = {
                if let err = note.userInfo?["error"] as? Error { return (err as NSError).localizedDescription }
                return nil
            }()
            Task { @MainActor [weak self] in
                self?.handleBackgroundDownloadCompletion(destinationURL: destinationURL, errorMessage: errorMessage)
            }
        }
    }

    @MainActor
    private func handleBackgroundDownloadCompletion(destinationURL: URL?, errorMessage: String?) {
        if let msg = errorMessage { print("[DownloadController] Background download failed: \(msg)"); return }
        guard let destinationURL else { return }
        
        // Try to reconcile main model weights completed via BackgroundDownloadManager.
        if let index = items.firstIndex(where: { item in
            let tmpName = item.quant.label + ".download"
            let destName = destinationURL.lastPathComponent
            // Match either the temporary .download path or the final weights filename
            return destName == tmpName || destName == item.quant.downloadURL.lastPathComponent
        }) {
            finalizeModelAfterBackgroundCompletion(itemIndex: index, tmpOrFinalURL: destinationURL)
            return
        }

        // If an mmproj projector finished, update its part progress.
        if let index = items.firstIndex(where: { $0.mmprojDestination?.path == destinationURL.path || destinationURL.lastPathComponent == $0.mmprojDestination?.lastPathComponent }) {
            // Mark projector done and recompute aggregate progress.
            let mainExpected = (items[index].mainExpectedBytes > 0) ? items[index].mainExpectedBytes : items[index].quant.sizeBytes
            items[index].mmprojProgress = 1
            items[index].mmprojFilename = destinationURL.lastPathComponent
            if items[index].mmprojBytesWritten == 0 { items[index].mmprojBytesWritten = max(items[index].mmprojBytesWritten, items[index].mmprojSize) }
            items[index].mmprojSpeed = 0
            items[index].mmprojDestination = nil
            refreshCombinedProgress(at: index)
            return
        }

        // Dataset file finished — best-effort UI update if we still have a matching item.
        if let index = datasetItems.firstIndex(where: { destinationURL.deletingLastPathComponent().lastPathComponent == $0.detail.id.split(separator: "/").last.map(String.init) }) {
            let removedID = datasetItems[index].id
            datasetItems[index].completed = true
            datasetItems[index].progress = 1.0
            datasetItems[index].speed = 0
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                self.datasetItems.removeAll { $0.id == removedID }
                if self.allItems.isEmpty { self.showOverlay = false }
            }
        }
    }

    private func finalizeModelAfterBackgroundCompletion(itemIndex: Int, tmpOrFinalURL: URL) {
        var item = items[itemIndex]
        guard !item.completed else { return }
        // Compute canonical directories and destination names
        let dir = InstalledModelsStore.baseDir(for: item.quant.format, modelID: item.detail.id)
        let finalURL = dir.appendingPathComponent(item.quant.downloadURL.lastPathComponent)
        // If the completed file is still under the temporary ".download" name, rename it now
        let fm = FileManager.default
        if tmpOrFinalURL.lastPathComponent.hasSuffix(".download") {
            try? fm.removeItemIfExists(at: finalURL)
            do { try fm.moveItem(at: tmpOrFinalURL, to: finalURL) } catch {
                print("[DownloadController] Failed to move completed file: \(error)")
            }
        }
        // Update artifacts.json to point at the weights for later recovery
        do {
            let artifactsURL = dir.appendingPathComponent("artifacts.json")
            var obj: [String: Any] = [:]
            if let data = try? Data(contentsOf: artifactsURL),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                obj = parsed
            }
            obj["weights"] = finalURL.lastPathComponent
            if obj["mmproj"] == nil { obj["mmproj"] = NSNull() }
            let out = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted])
            try? out.write(to: artifactsURL)
        } catch {}

        // Mark UI state
        items[itemIndex].completed = true
        items[itemIndex].progress = 1.0
        items[itemIndex].speed = 0
        items[itemIndex].error = nil

        // Register minimal InstalledModel; deeper metadata (layers, capabilities) will be scanned later.
        let installed = InstalledModel(
            modelID: item.detail.id,
            quantLabel: item.quant.label,
            url: finalURL,
            format: item.quant.format,
            sizeBytes: item.quant.sizeBytes,
            lastUsed: nil,
            installDate: Date(),
            checksum: item.quant.sha256,
            isFavourite: false,
            totalLayers: 0
        )
#if os(macOS) && !canImport(UIKit)
        if let manager = self.modelManager as? AppModelManager { manager.install(installed) }
#else
        self.modelManager?.install(installed)
#endif
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            self.items.removeAll { $0.id == item.id }
            if self.allItems.isEmpty { self.showOverlay = false }
        }
    }
	
#if os(macOS) && !canImport(UIKit)
    func configure(modelManager: AnyObject, datasetManager: DatasetManager) {
		self.modelManager = modelManager
		self.datasetManager = datasetManager
	}
#else
    func configure(modelManager: AppModelManager, datasetManager: DatasetManager) {
		self.modelManager = modelManager
		self.datasetManager = datasetManager
	}
#endif
	
    /// Returns the best-known byte counts for main weights and projector, grounded in on-disk
    /// file sizes to avoid UI desync when delegate progress callbacks are delayed or missing.
    private func byteCounts(for item: Item) -> (mainWritten: Int64, mainExpected: Int64, mmWritten: Int64, mmExpected: Int64) {
        let fm = FileManager.default
        // Main weights: prefer the temp ".download" file if present, else the final weights path.
        var mainBytes = item.mainBytesWritten
        let baseDir = InstalledModelsStore.baseDir(for: item.quant.format, modelID: item.detail.id)
        let mainTmp = baseDir.appendingPathComponent("\(item.quant.label).download")
        if let attrs = try? fm.attributesOfItem(atPath: mainTmp.path),
           let sz = attrs[.size] as? Int64 {
            mainBytes = max(mainBytes, sz)
        } else {
            let mainFinal = baseDir.appendingPathComponent(item.quant.downloadURL.lastPathComponent)
            if let attrs = try? fm.attributesOfItem(atPath: mainFinal.path),
               let sz = attrs[.size] as? Int64 {
                mainBytes = max(mainBytes, sz)
            }
        }

        // Projector: check the in-flight destination first, then the final path.
        var mmBytes = item.mmprojBytesWritten
        let mmNameFromArtifacts: String? = {
            let artifactsURL = baseDir.appendingPathComponent("artifacts.json")
            if let data = try? Data(contentsOf: artifactsURL),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let name = parsed["mmproj"] as? String,
               !name.isEmpty,
               name != "<null>" {
                return name
            }
            return nil
        }()
        let mmName = item.mmprojDestination?.lastPathComponent ?? item.mmprojFilename ?? mmNameFromArtifacts
        func probe(_ url: URL) {
            if let attrs = try? fm.attributesOfItem(atPath: url.path),
               let sz = attrs[.size] as? Int64 {
                mmBytes = max(mmBytes, sz)
            }
        }
        if let dest = item.mmprojDestination { probe(dest) }
        if let name = mmName {
            probe(baseDir.appendingPathComponent(name))
            probe(baseDir.appendingPathComponent(name + ".download"))
        }
        // Fallback: heuristic search for any mmproj-like file in the model directory
        if mmBytes == item.mmprojBytesWritten && mmBytes == 0 && item.mmprojSize > 0 {
            if let contents = try? fm.contentsOfDirectory(atPath: baseDir.path) {
                if let first = contents.first(where: { $0.localizedCaseInsensitiveContains("mmproj") || $0.localizedCaseInsensitiveContains("projector") }) {
                    probe(baseDir.appendingPathComponent(first))
                    probe(baseDir.appendingPathComponent(first + ".download"))
                }
            }
        }

        // Expected totals should never be smaller than bytes already written.
        let mainExpected = max(item.mainExpectedBytes, mainBytes)
        let mmExpected = max(item.mmprojSize, mmBytes)

        return (mainBytes, mainExpected, mmBytes, mmExpected)
    }

    /// Recompute combined progress for a given item index using absolute bytes.
    private func refreshCombinedProgress(at index: Int) {
        let counts = byteCounts(for: items[index])
        items[index].mainBytesWritten = counts.mainWritten
        items[index].mainExpectedBytes = counts.mainExpected
        items[index].mmprojBytesWritten = counts.mmWritten
        items[index].mmprojSize = counts.mmExpected // keep expected in sync if it grew via on-disk probe

        let totalExpected = max(1, counts.mainExpected + counts.mmExpected)
        let doneBytes = counts.mainWritten + counts.mmWritten
        items[index].progress = Double(doneBytes) / Double(totalExpected)
    }

    /// Best-effort fallback: if the files exist on disk and progress is ~done but the stream
    /// never emitted `.finished`, finalize and install the model.
    private func autoFinalizeCompletedOnDisk() {
        guard !items.isEmpty else { return }
        let fm = FileManager.default
        for idx in items.indices {
            if items[idx].completed { continue }
            // Require near-complete progress to avoid hijacking active downloads.
            if items[idx].progress < 0.995 { continue }
            let baseDir = InstalledModelsStore.baseDir(for: items[idx].quant.format, modelID: items[idx].detail.id)
            let finalURL = baseDir.appendingPathComponent(items[idx].quant.downloadURL.lastPathComponent)
            guard fm.fileExists(atPath: finalURL.path) else { continue }

            // If a projector is expected, ensure it exists (or we at least have bytes for it).
            if items[idx].mmprojSize > 0 {
                let counts = byteCounts(for: items[idx])
                let mmName = items[idx].mmprojFilename
                let mmURL = mmName != nil ? baseDir.appendingPathComponent(mmName!) : nil
                let mmPresent = (counts.mmWritten > 0) || (mmURL != nil && fm.fileExists(atPath: mmURL!.path))
                if !mmPresent { continue }
            }

            finalizeModelAfterBackgroundCompletion(itemIndex: idx, tmpOrFinalURL: finalURL)
        }
    }

	private func key(for detail: ModelDetails, quant: QuantInfo) -> String {
		"\(detail.id)-\(quant.label)"
	}
	
	func start(detail: ModelDetails, quant: QuantInfo) {
		let id = key(for: detail, quant: quant)
		if tasks[id] != nil { return }

		if !items.contains(where: { $0.id == id }) {
			let item = Item(detail: detail, quant: quant)
			items.append(item)
		}
		showOverlay = true
		
			let t = Task { [weak self] in
				guard let self else { return }
				// Always check for an mmproj companion when downloading GGUF models.
				if quant.format == .gguf {
					let llmDir = InstalledModelsStore.baseDir(for: .gguf, modelID: detail.id)
					do {
						try FileManager.default.createDirectory(at: llmDir, withIntermediateDirectories: true)
						// Persist a repo hint to help re-home after relaunch/sandbox change
						let repoFile = llmDir.appendingPathComponent("repo.txt")
					if !FileManager.default.fileExists(atPath: repoFile.path) {
						try? detail.id.data(using: .utf8)?.write(to: repoFile)
					}
				} catch {
					await MainActor.run {
						if let idx = self.items.firstIndex(where: { $0.id == id }) {
							self.items[idx].error = .permanentError("Failed to create model directory")
						}
						self.tasks[id] = nil
					}
					return
					}
					// Discover mmproj via HF API file list; search the quant's repo first, then fall back to the base repo
					var selected: (name: String, url: URL, size: Int64)? = nil
					var repoCandidates: [String] = []
                    if let quantRepo = self.huggingFaceRepoID(from: quant.downloadURL) {
					repoCandidates.append(quantRepo)
				}
					if !repoCandidates.contains(detail.id) {
						repoCandidates.append(detail.id)
					}
					let token = UserDefaults.standard.string(forKey: "huggingFaceToken")?.trimmingCharacters(in: .whitespacesAndNewlines)
					for repo in repoCandidates {
						if let proj = await VisionModelDetector.projectorMetadata(repoId: repo, token: token) {
							let escapedRepo = repo.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repo
							let url = URL(string: "https://huggingface.co/\(escapedRepo)/resolve/main/\(proj.filename)?download=1")!
							var size = proj.size
							if size <= 0 {
								let headSize = await self.fetchRemoteSize(url)
								if headSize > 0 { size = headSize }
							}
							selected = (proj.filename, url, size)
							break
						}
					}
                await MainActor.run {
                    if let idx = self.items.firstIndex(where: { $0.id == id }) {
                        self.items[idx].mmprojSize = selected?.size ?? 0
                        self.items[idx].mmprojFilename = selected?.name
                        if let size = selected?.size, size > 0, self.loggedMMProjExpected[id] != size {
                            self.loggedMMProjExpected[id] = size
                            self.logDetectedSize(kind: "Projector", id: id, bytes: size, source: "catalog")
                        }
                    }
				}
				// Persist that we checked for mmproj
				do {
					let artifactsURL = llmDir.appendingPathComponent("artifacts.json")
					var obj: [String: Any] = [:]
					if let data = try? Data(contentsOf: artifactsURL),
					   let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
						obj = parsed
					}
					obj["mmprojChecked"] = true
					// If not found, set explicit null for mmproj so UI can report absence
					if selected == nil {
						obj["mmproj"] = NSNull()
					}
					let out = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted])
					try? out.write(to: artifactsURL)
				} catch {}
                // If a projector file is offered, download it even if size is unknown (we'll learn expected via the task)
                if let sel = selected {
					let mmprojFile = sel.name
					let mmprojURL = sel.url
					let mmprojDest = llmDir.appendingPathComponent(mmprojFile)
					if !FileManager.default.fileExists(atPath: mmprojDest.path) {
						do {
                            var req = URLRequest(url: mmprojURL)
                            // Pass auth if available
                            if let token = UserDefaults.standard.string(forKey: "huggingFaceToken"), !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                            }
                            req.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
                            req.setValue("Noema/1.0 (+https://noema.app)", forHTTPHeaderField: "User-Agent")
							print("[Downloader] ▶︎ Downloading \(mmprojFile)…")
							// Prepare temp file for resume
							let tmp = llmDir.appendingPathComponent("\(mmprojFile).download")
							var startOffset: Int64 = 0
							if FileManager.default.fileExists(atPath: tmp.path) {
								if let attrs = try? FileManager.default.attributesOfItem(atPath: tmp.path), let sz = attrs[.size] as? Int64 { startOffset = sz }
							} else {
								FileManager.default.createFile(atPath: tmp.path, contents: nil)
							}
							let handle = try FileHandle(forWritingTo: tmp)
							try? handle.seekToEnd()
							// Legacy URLSession delegate removed; BackgroundDownloadManager is used below for robust progress/pausing
                        // Background download to final destination; compute smoothed progress / speed
                        // Throttle for visible progress ticks (bytes sampling handled via @MainActor properties)
                        var lastProgressTickAt: Date = .distantPast
                        var lastProgressReported: Double = 0
                        // Record destination immediately so cancel can remove partial file even before first progress tick
                        Task { @MainActor in
                            if let i = self.items.firstIndex(where: { $0.id == id }) {
                                self.items[i].mmprojDestination = mmprojDest
                            }
                        }
                        try await BackgroundDownloadManager.shared.download(
                            request: req,
                            to: mmprojDest,
                            expectedSize: (sel.size > 0 ? sel.size : nil),
                            progress: { prog in
                                let now = Date()
                                let pmm = min(prog, 0.999)
                                // Throttle UI updates independent of speed sampling
                                let shouldTick = now.timeIntervalSince(lastProgressTickAt) >= 0.10 || (prog - lastProgressReported) >= 0.01
                                guard shouldTick else { return }
                                lastProgressTickAt = now
                                lastProgressReported = prog
                                Task { @MainActor in
                                    if let idx = self.items.firstIndex(where: { $0.id == id }) {
                                        self.items[idx].mmprojProgress = pmm
                                        // Prefer absolute-bytes aggregation; on-disk probe keeps us accurate.
                                        self.refreshCombinedProgress(at: idx)
                                        // Record destination so pause/cancel can stop the background task
                                        self.items[idx].mmprojDestination = mmprojDest
                                    }
                                }
                            },
                            progressBytes: { written, expected in
                                Task { @MainActor in
                                    // Identify the active item by captured id
                                    guard let idx = self.items.firstIndex(where: { $0.id == id }) else { return }

                                    // 1) Progress using absolute bytes
                                    self.items[idx].mmprojBytesWritten = written
                                    if expected > 0 {
                                        let previous = self.items[idx].mmprojSize
                                        self.items[idx].mmprojSize = expected
                                        if self.loggedMMProjExpected[id] != expected || previous != expected {
                                            self.loggedMMProjExpected[id] = expected
                                            self.logDetectedSize(kind: "Projector", id: id, bytes: expected, source: "Content-Length")
                                        }
                                    }
                                    self.refreshCombinedProgress(at: idx)

                                    // 2) Speed calculation using per-item samplers (EMA)
                                    let now = Date()
                                    let lastTime = self.lastMMProjSpeedSampleAt[id]
                                    let lastBytes = self.lastMMProjBytesSample[id]

                                    if lastTime == nil || lastBytes == nil {
                                        self.lastMMProjSpeedSampleAt[id] = now
                                        self.lastMMProjBytesSample[id] = written
                                        return
                                    }

                                    let dt = now.timeIntervalSince(lastTime!)
                                    guard dt >= 0.25 else { return } // ~4 Hz

                                    let bytesDelta = written - lastBytes!
                                    let rawSpeed = dt > 0 ? Double(bytesDelta) / dt : 0.0
                                    let instSpeed = max(0, min(rawSpeed, self.maxInstantaneousSpeed))

                                    self.lastMMProjSpeedSampleAt[id] = now
                                    self.lastMMProjBytesSample[id] = written

                                    let alpha = self.speedEMAAlpha
                                    let prevSpeed = self.items[idx].mmprojSpeed
                                    let newSpeed = (prevSpeed > 0) ? (1 - alpha) * prevSpeed + alpha * instSpeed : instSpeed
                                    self.items[idx].mmprojSpeed = newSpeed
                                    self.items[idx].speed = min(self.maxInstantaneousSpeed, self.items[idx].mainSpeed + self.items[idx].mmprojSpeed)
                                    self.lastModelSpeedSampleAt[id] = now
                                }
                            }
                        )
                        // Validate GGUF magic to avoid saving HTML error pages
                        if let fh = try? FileHandle(forReadingFrom: mmprojDest) {
                            defer { try? fh.close() }
                            let magic = try fh.read(upToCount: 4) ?? Data()
                            if magic != Data("GGUF".utf8) { throw URLError(.cannotParseResponse) }
                        }
                            // Update artifacts.json with mmproj reference
                            do {
                                let artifactsURL = llmDir.appendingPathComponent("artifacts.json")
                                var obj: [String: Any] = [:]
                                if let data = try? Data(contentsOf: artifactsURL),
                                   let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                    obj = parsed
                                }
                                obj["mmproj"] = mmprojDest.lastPathComponent
                                obj["mmprojChecked"] = true
                                let out = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted])
                                try? out.write(to: artifactsURL)
                            } catch {}
                            print("[Downloader] ✓ \(mmprojFile) downloaded successfully.")
                            await MainActor.run {
                                if let idx = self.items.firstIndex(where: { $0.id == id }) {
                                    self.items[idx].mmprojProgress = 1
                                    self.items[idx].mmprojFilename = mmprojDest.lastPathComponent
                                    self.items[idx].mmprojBytesWritten = max(self.items[idx].mmprojBytesWritten, self.items[idx].mmprojSize)
                                    self.items[idx].mmprojDestination = nil
                                    self.items[idx].mmprojSpeed = 0
                                    // Recompute combined progress (main could still be 0 here) using absolute bytes
                                    self.refreshCombinedProgress(at: idx)
                                }
                            }
						} catch {
							// Best-effort: proceed without mmproj on failure
							print("[Downloader] ⚠︎ mmproj download failed: \(error.localizedDescription)")
						}
					} else {
						// mmproj already present
						// Ensure artifacts.json reflects presence
                    do {
                        let artifactsURL = llmDir.appendingPathComponent("artifacts.json")
                        var obj: [String: Any] = [:]
                        if let data = try? Data(contentsOf: artifactsURL),
                           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            obj = parsed
                        }
                        obj["mmproj"] = mmprojDest.lastPathComponent
                        obj["mmprojChecked"] = true
                        let out = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted])
                        try? out.write(to: artifactsURL)
                    } catch {}
                    await MainActor.run {
                        if let idx = self.items.firstIndex(where: { $0.id == id }) {
                            self.items[idx].mmprojProgress = 1
                            // Treat an already-present projector as completed bytes so the combined
                            // progress denominator doesn’t make the main weights look “stuck”.
                            // Previously we set only the progress flag, leaving `mmprojBytesWritten`
                            // at zero, which understated overall progress by the projector size.
                            let existingBytes = self.items[idx].mmprojSize
                            if existingBytes > 0 {
                                self.items[idx].mmprojBytesWritten = existingBytes
                                self.items[idx].mmprojSpeed = 0
                                let mainExpected = (self.items[idx].mainExpectedBytes > 0)
                                    ? self.items[idx].mainExpectedBytes
                                    : self.items[idx].quant.sizeBytes
                                self.items[idx].mainExpectedBytes = mainExpected
                                self.items[idx].mmprojFilename = mmprojDest.lastPathComponent
                                self.refreshCombinedProgress(at: idx)
                            }
                        }
                    }
                }
            }
        }
		let stream = await manager.download(quant, for: detail.id)
		for await event in stream {
			await MainActor.run {
				guard let idx = self.items.firstIndex(where: { $0.id == id }) else { return }
				switch event {
                        case .started(let expected):
                            let detected = expected ?? 0
                            if detected > 0 {
                                let previous = self.items[idx].mainExpectedBytes
                                self.items[idx].mainExpectedBytes = detected
                                if self.loggedMainExpected[id] != detected || previous != detected {
                                    self.loggedMainExpected[id] = detected
                                    self.logDetectedSize(kind: "Model", id: id, bytes: detected, source: "metadata")
                                }
                            }
                        case .progress(let p, let bytesReported, let expectedFromSession, let managerSpeed):
                            let pClamped = min(p, 0.999)
                            self.items[idx].mainProgress = pClamped
                            // Compute bytes-so-far from the best-known expected size; fall back to quant size
                            let effectiveExpected: Int64 = (expectedFromSession > 0) ? expectedFromSession : self.items[idx].quant.sizeBytes
                            let derivedBytes = Int64(Double(max(effectiveExpected, 0)) * pClamped)
                            let bytesSoFar = (bytesReported > 0 ? bytesReported : derivedBytes)
                            // Prefer the session-reported expected size (includes resume offsets) and allow shrinking
                            // if registry metadata overestimates the file. Fall back to catalog size when unknown.
                            let candidate = effectiveExpected > 0 ? effectiveExpected : self.items[idx].quant.sizeBytes
                            let previousExpected = self.items[idx].mainExpectedBytes
                            if candidate > 0 {
                                self.items[idx].mainExpectedBytes = candidate
                                if self.loggedMainExpected[id] != candidate || previousExpected != candidate {
                                    self.loggedMainExpected[id] = candidate
                                    let source = expectedFromSession > 0 ? "Content-Length" : "metadata"
                                    self.logDetectedSize(kind: "Model", id: id, bytes: candidate, source: source)
                                }
                            }
                            // Ground the byte counter in on-disk size to avoid under-reporting when
                            // delegate callbacks are sparse or resume offsets hide prior bytes.
                            self.items[idx].mainBytesWritten = max(bytesSoFar, self.byteCounts(for: self.items[idx]).mainWritten)
                            // Use manager-reported instantaneous speed; EMA smooth and aggregate
                            let now = Date()
                            let prev = self.items[idx].mainSpeed
                            let alpha = self.speedEMAAlpha
                            let inst = max(0, min(managerSpeed, self.maxInstantaneousSpeed))
                            self.items[idx].mainSpeed = prev > 0 ? (1 - alpha) * prev + alpha * inst : inst
                            self.items[idx].speed = min(self.maxInstantaneousSpeed, self.items[idx].mainSpeed + self.items[idx].mmprojSpeed)
                            self.lastModelSpeedSampleAt[self.items[idx].id] = now
                            self.lastMainSpeedSampleAt[id] = now
                            self.lastMainBytesSample[id] = bytesSoFar
                            // Recompute combined progress using absolute bytes when possible
                            self.refreshCombinedProgress(at: idx)
					case .finished(let installed):
						self.items[idx].mainProgress = 1
						self.items[idx].progress = 1
						self.items[idx].speed = 0
						self.items[idx].completed = true
						self.items[idx].error = nil
#if os(macOS) && !canImport(UIKit)
						if let manager = self.modelManager as? AppModelManager {
							manager.install(installed)
						}
#else
						self.modelManager?.install(installed)
#endif
						// If a dataset was just downloaded via dataset flow, DatasetManager triggers indexing itself.
						self.tasks[id] = nil
						// Clear per-item main speed samplers
						self.lastMainSpeedSampleAt[id] = nil
						self.lastMainBytesSample[id] = nil
						Task { @MainActor in
							try? await Task.sleep(for: .seconds(3))
							self.items.removeAll { $0.id == id }
							if self.allItems.isEmpty {
								self.showOverlay = false
							}
						}
					case .cancelled:
						self.items.removeAll { $0.id == id }
						self.tasks[id] = nil
						// Clear main speed samplers for this id
						self.lastMainSpeedSampleAt[id] = nil
						self.lastMainBytesSample[id] = nil
						if self.allItems.isEmpty { self.showOverlay = false }
                                        case .paused(let p):
                                                let pClamped = min(p, 0.999)
                                                self.items[idx].mainProgress = pClamped
                                                self.items[idx].speed = 0
                                                self.items[idx].error = nil
                                                self.paused.insert(id)
                                                // Recompute combined progress using absolute bytes
                                                self.refreshCombinedProgress(at: idx)
                                                // Clear task so resume can restart
                                                self.tasks[id] = nil
					case .failed(let error):
						self.items[idx].speed = 0
						self.tasks[id] = nil
						
						// Categorize error type
						let downloadError = self.categorizeError(error)
						self.items[idx].error = downloadError
						
						if downloadError.isRetryable {
							// Network errors are retryable - keep in paused state
							self.paused.insert(id)
						} else {
							// Permanent errors - remove after delay
							Task { @MainActor in
								try? await Task.sleep(for: .seconds(5))
								self.items.removeAll { $0.id == id }
								self.lastMainSpeedSampleAt[id] = nil
								self.lastMainBytesSample[id] = nil
								if self.allItems.isEmpty {
									self.showOverlay = false
								}
							}
						}
                                        case .networkError(let error, let progress):
                                                let pClamped = min(progress, 0.999)
                                                self.items[idx].mainProgress = pClamped
                                                self.items[idx].speed = 0
                                                self.items[idx].retryCount += 1
                                                // Recompute combined progress
                                                let mmBytes = Double(self.items[idx].mmprojSize)
                                                let mainBytes = Double(self.items[idx].quant.sizeBytes)
                                                let denom = mmBytes + mainBytes
                                                let combined = denom > 0 ? ((mmBytes * self.items[idx].mmprojProgress) + (mainBytes * pClamped)) / denom : pClamped
                                                self.items[idx].progress = combined
                                                // Clear current task to allow restart
                                                self.tasks[id] = nil
                                                // Backoff grows but caps at 60s
                                                let delay = min(pow(2.0, Double(self.items[idx].retryCount)), 60)
                                                Task { @MainActor in
                                                        try? await Task.sleep(for: .seconds(delay))
                                                        await self.waitForNetworkConnectivity()
                                                        if let item = self.items.first(where: { $0.id == id }) {
                                                                self.start(detail: item.detail, quant: item.quant)
                                                        }
                                                }
					default:
						break
					}
				}
			}
		}
		
		tasks[id] = t
	}
	
func pause(itemID: String) {
		paused.insert(itemID)
		// Derive components
		if let item = items.first(where: { $0.id == itemID }) {
			Task { await manager.pause(modelID: item.detail.id, quantLabel: item.quant.label) }
			// Also pause any in-flight mmproj background download
			if let dest = item.mmprojDestination {
				BackgroundDownloadManager.shared.pause(destination: dest)
			}
		}
}
	
	func resume(itemID: String) {
		paused.remove(itemID)
		// Find model details to restart; this will resume from temp file
		if let idx = items.firstIndex(where: { $0.id == itemID }) {
			items[idx].error = nil // Clear error state
			items[idx].retryCount = 0 // Reset retry count on manual resume
			let item = items[idx]
			start(detail: item.detail, quant: item.quant)
		}
	}
	
	private func categorizeError(_ error: Error) -> DownloadError {
		let nsError = error as NSError
		
		// Network-related errors that should be retryable
		let networkErrorCodes: Set<Int> = [
			NSURLErrorNotConnectedToInternet,
			NSURLErrorTimedOut,
			NSURLErrorCannotConnectToHost,
			NSURLErrorNetworkConnectionLost,
			NSURLErrorDNSLookupFailed,
			NSURLErrorCannotFindHost,
			NSURLErrorInternationalRoamingOff,
			NSURLErrorCallIsActive,
			NSURLErrorDataNotAllowed
		]
		
		if nsError.domain == NSURLErrorDomain && networkErrorCodes.contains(nsError.code) {
			let message: String
			switch nsError.code {
			case NSURLErrorNotConnectedToInternet:
				message = "No internet connection"
			case NSURLErrorTimedOut:
				message = "Connection timed out"
			case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost:
				message = "Cannot reach server"
			case NSURLErrorNetworkConnectionLost:
				message = "Connection lost"
			case NSURLErrorDNSLookupFailed:
				message = "DNS lookup failed"
			default:
				message = "Network error"
			}
			return .networkError(message)
		}
		
		// HTTP errors that might be retryable
		if let httpError = error as? URLError,
		   let code = (httpError.userInfo["NSErrorFailingURLStringKey"] as? String),
		   let response = httpError.userInfo["NSErrorFailingURLKey"] as? HTTPURLResponse {
			if response.statusCode >= 500 { // Server errors
				return .networkError("Server error (\(response.statusCode))")
			}
		}
		
		// All other errors are permanent
		return .permanentError(error.localizedDescription)
	}
	
        private func networkErrorMessage(_ error: Error) -> String {
                let nsError = error as NSError
		
		if nsError.domain == NSURLErrorDomain {
			switch nsError.code {
			case NSURLErrorNotConnectedToInternet:
				return "No internet connection"
			case NSURLErrorTimedOut:
				return "Connection timed out"
			case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost:
				return "Cannot reach server"
			case NSURLErrorNetworkConnectionLost:
				return "Connection lost"
			case NSURLErrorDNSLookupFailed:
				return "DNS lookup failed"
			default:
				return "Network error"
			}
		}
		
                return "Connection failed"
        }

        private func waitForNetworkConnectivity() async {
                await withCheckedContinuation { continuation in
                        let monitor = NWPathMonitor()
                        let queue = DispatchQueue(label: "noema.network.monitor")
                        monitor.pathUpdateHandler = { path in
                                if path.status == .satisfied {
                                        monitor.cancel()
                                        continuation.resume()
                                }
                        }
                        monitor.start(queue: queue)
                }
        }
	
    func startLeap(entry: LeapCatalogEntry) {
        let id = entry.slug
        if tasks[id] != nil { return }
        // Ensure single UI entry per slug
        if !leapItems.contains(where: { $0.id == id }) {
            let item = LeapItem(entry: entry)
            self.objectWillChange.send()
            leapItems.append(item)
        }
        showOverlay = true
		
		let t = Task { [weak self] in
			guard let self else { return }
			for await event in LeapBundleDownloader.shared.download(entry) {
				await MainActor.run {
					guard let idx = self.leapItems.firstIndex(where: { $0.id == id }) else { return }
                switch event {
                case .started(let total):
                    self.objectWillChange.send()
                    if let t = total, t > 0 {
                        self.leapItems[idx].expectedBytes = t
                        if self.loggedLeapExpected[id] != t {
                            self.loggedLeapExpected[id] = t
                            self.logDetectedSize(kind: "SLM", id: id, bytes: t, source: "metadata")
                        }
                    }
                case .progress(let p, _, let expected, let speed):
                    self.objectWillChange.send()
                    let pClamped = min(p, 0.999)
                    self.leapItems[idx].progress = pClamped
                    let previous = self.leapItems[idx].speed
                    let alpha = self.speedEMAAlpha
                    let clipped = min(speed, self.maxInstantaneousSpeed)
                    self.leapItems[idx].speed = previous * (1 - alpha) + clipped * alpha
                    self.lastLeapSpeedSampleAt[self.leapItems[idx].id] = Date()
                    self.leapItems[idx].verifying = false
                    if expected > 0 {
                        let prev = self.leapItems[idx].expectedBytes
                        self.leapItems[idx].expectedBytes = expected
                        if self.loggedLeapExpected[id] != expected || prev != expected {
                            self.loggedLeapExpected[id] = expected
                            self.logDetectedSize(kind: "SLM", id: id, bytes: expected, source: "Content-Length")
                        }
                    }
                case .finished(let installed):
                    self.objectWillChange.send()
                    self.leapItems[idx].progress = 1
                    self.leapItems[idx].speed = 0
                    self.leapItems[idx].completed = true
                    self.leapItems[idx].verifying = false
                    if self.leapItems[idx].expectedBytes <= 0 { self.leapItems[idx].expectedBytes = Int64(installed.sizeBytes) }
#if os(macOS) && !canImport(UIKit)
                    if let manager = self.modelManager as? AppModelManager {
                        manager.install(installed)
                    }
#else
                    self.modelManager?.install(installed)
#endif
                    self.tasks[id] = nil
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(3))
                        self.objectWillChange.send()
                        self.leapItems.removeAll { $0.id == id }
                        if self.allItems.isEmpty { self.showOverlay = false }
                    }
                case .cancelled:
                    self.objectWillChange.send()
                    self.leapItems.removeAll { $0.id == id }
                    self.tasks[id] = nil
                    if self.allItems.isEmpty { self.showOverlay = false }
                case .networkError(_, let progress):
                    self.objectWillChange.send()
                    // Keep the item and schedule a retry with backoff
                    self.leapItems[idx].progress = progress
                    self.leapItems[idx].speed = 0
                    self.leapItems[idx].verifying = false
                    self.tasks[id] = nil
                    self.leapItems[idx].retryCount += 1
                    let delay = min(pow(2.0, Double(self.leapItems[idx].retryCount)), 60)
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(delay))
                        await self.waitForNetworkConnectivity()
                        if self.tasks[id] == nil && self.leapItems.contains(where: { $0.id == id }) {
                            self.startLeap(entry: entry)
                        }
                    }
                case .failed(_):
                    self.objectWillChange.send()
                    self.leapItems[idx].completed = false
                    self.leapItems[idx].verifying = false
                    self.tasks[id] = nil
                    if self.allItems.isEmpty { self.showOverlay = false }
                default:
                    break
                }
				}
			}
		}
		
		tasks[id] = t
	}
	
        func startDataset(detail: DatasetDetails) {
                let id = detail.id
                if tasks[id] != nil { return }
                // Determine upfront file list and expected size using any known lengths from `detail`
                let supported: Set<String> = ["pdf", "epub", "txt", "md", "json", "jsonl", "csv", "tsv"]
                var filesToDownload: [DatasetFile] = detail.files.filter { f in
                        let ext = f.downloadURL.pathExtension.lowercased()
                        return supported.contains(ext)
                }
                // For OTL datasets, prefer the PDF file to match the size shown in search results
                if detail.id.hasPrefix("OTL/"),
                   let pdf = filesToDownload.first(where: { $0.downloadURL.pathExtension.lowercased() == "pdf" }) {
                        filesToDownload = [pdf]
                }
                var upfrontTotal: Int64 = filesToDownload.reduce(0) { $0 + $1.sizeBytes }

                var item = DatasetItem(detail: detail)
                if upfrontTotal > 0 {
                        item.expectedBytes = upfrontTotal
                        if loggedDatasetExpected[id] != upfrontTotal {
                                loggedDatasetExpected[id] = upfrontTotal
                                logDetectedSize(kind: "Dataset", id: id, bytes: upfrontTotal, source: "metadata")
                        }
                }
                item.downloadedBytes = 0
                objectWillChange.send()
                if let idxExisting = datasetItems.firstIndex(where: { $0.id == id }) {
                        datasetItems[idxExisting] = item
                } else {
                        datasetItems.append(item)
                }
                showOverlay = true

                let t = Task { [weak self] in
                        guard let self else { return }
                        // Outer do/catch not required; inner operations handle their own errors
                                var filesToDownload = filesToDownload
                                // Some sources (e.g., OTL manual entries or landing pages) lack a file extension.
                                // Try to resolve a direct PDF/EPUB URL via HEAD/partial GET when nothing matched.
                                if filesToDownload.isEmpty {
                                        func resolveDirectURL(_ original: URL) async -> (URL, Int64)? {
                                                // 1) HEAD
                                                var head = URLRequest(url: original)
                                                head.httpMethod = "HEAD"
                                                head.setValue("application/pdf, application/epub+zip;q=0.9, */*;q=0.8", forHTTPHeaderField: "Accept")
                                                head.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
						do {
							if NetworkKillSwitch.isEnabled { throw URLError(.notConnectedToInternet) }
							NetworkKillSwitch.track(session: URLSession.shared)
							let (_, resp) = try await URLSession.shared.data(for: head)
							if let http = resp as? HTTPURLResponse {
								if let lenStr = http.value(forHTTPHeaderField: "Content-Length"), let len = Int64(lenStr), len > 0 { return (original, len) }
								if let range = http.value(forHTTPHeaderField: "Content-Range"), let total = range.split(separator: "/").last, let len = Int64(total) { return (original, len) }
								if http.expectedContentLength > 0 { return (original, http.expectedContentLength) }
							}
						} catch {}
						// 2) naive fetch
						var get = URLRequest(url: original)
						get.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
						if NetworkKillSwitch.isEnabled { return nil }
						NetworkKillSwitch.track(session: URLSession.shared)
						if let (data, resp) = try? await URLSession.shared.data(for: get), let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
							// crude content-sniffing
							let mime = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
							let isPDF = mime.contains("pdf") || data.prefix(4) == Data([0x25, 0x50, 0x44, 0x46])
							let isEPUB = mime.contains("epub") || data.starts(with: Data([0x50, 0x4b])) // zip signature
							if isPDF || isEPUB {
								return (original, Int64(data.count))
							}
						}
						return nil
					}
					// Use the first available file URL as a candidate landing URL
					if let candidate = detail.files.first,
					   let (resolved, size) = await resolveDirectURL(candidate.downloadURL) {
						filesToDownload = [DatasetFile(id: resolved.absoluteString, name: resolved.lastPathComponent, sizeBytes: size, downloadURL: resolved)]
                                        }
                                }

                                // Ensure target dataset directory exists
                                let baseDir = DownloadController.datasetBaseDir(for: id)
				do { try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true) } catch { return }
				// Persist a human-readable title alongside the dataset when available
				if let title = detail.displayName, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
					let titleURL = baseDir.appendingPathComponent("title.txt")
                                        try? title.data(using: .utf8)?.write(to: titleURL)
                                }

                                var totalSize: Int64 = upfrontTotal
                                if totalSize == 0 {
                                        for file in filesToDownload {
                                                totalSize += await self.fetchRemoteSize(file.downloadURL)
                                        }
                                        await MainActor.run {
                                                if let idx = self.datasetItems.firstIndex(where: { $0.id == id }) {
                                                        self.objectWillChange.send()
                                                        self.datasetItems[idx].expectedBytes = totalSize
                                                        if totalSize > 0, self.loggedDatasetExpected[id] != totalSize {
                                                                self.loggedDatasetExpected[id] = totalSize
                                                                self.logDetectedSize(kind: "Dataset", id: id, bytes: totalSize, source: "HEAD")
                                                        }
                                                }
                                        }
                                }

                                var completedBytes: Int64 = 0
                                // Fallback tracker for unknown total sizes: equal-share per file
                                let fileCount = max(filesToDownload.count, 1)
                                var completedFiles: Int = 0
				
				// Download each file sequentially for now (can parallelize later)
                                for file in filesToDownload {
                                        let fileURL = file.downloadURL
                    var req = URLRequest(url: fileURL)
                    req.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
                    req.setValue("Noema/1.0 (+https://noema.app)", forHTTPHeaderField: "User-Agent")
                                        var knownExpected: Int64 = file.sizeBytes
                                        if knownExpected <= 0 { knownExpected = await self.fetchRemoteSize(fileURL) }
                                        let dest = baseDir.appendingPathComponent(fileURL.lastPathComponent)
                                        var speedLastTime: Date? = nil
                                        var lastBytes: Int64 = 0
                                        var lastProgressTickAt: Date = .distantPast
                                        var attempt = 0
                                        retryLoop: while true {
                                        do {
                                        try await BackgroundDownloadManager.shared.download(
                                            request: req,
                                            to: dest,
                                            expectedSize: knownExpected,
                                            progress: { [weak self] frac in
                                                guard let self else { return }
                                                // Avoid reporting 100% until completion to prevent perceived stalls at 100%
                                                let f = max(0, min(frac, 0.999))
                                                let now = Date()
                                                if now.timeIntervalSince(lastProgressTickAt) < 0.10 { return }
                                                lastProgressTickAt = now
                                                // Progress callback may be non-async; hop to main safely.
                                                Task { @MainActor in
                                                    if let idx = self.datasetItems.firstIndex(where: { $0.id == id }) {
                                                        self.objectWillChange.send()
                                                        if totalSize > 0 {
                                                            let already = completedBytes
                                                            let cur = Int64(Double(max(knownExpected, 0)) * f)
                                                            self.datasetItems[idx].downloadedBytes = already + cur
                                                            let denom = Double(totalSize)
                                                            let prog = denom > 0 ? Double(self.datasetItems[idx].downloadedBytes) / denom : 0
                                                            self.datasetItems[idx].progress = max(0, min(1, prog))
                                                        } else {
                                                            // Unknown total size (e.g., OTL). Use per-file equal-share fallback
                                                            let prog = (Double(completedFiles) + Double(f)) / Double(fileCount)
                                                            self.datasetItems[idx].progress = max(0, min(1, prog))
                                                        }
                                                    }
                                                }
                                            },
                                            progressBytes: { [weak self] written, expected in
                                                guard let self else { return }
                                                let now = Date()
                                                // Initialize sampler on the first callback to avoid dt==0 loop
                                                if speedLastTime == nil {
                                                    speedLastTime = now
                                                    lastBytes = written
                                                }
                                                // If we didn't know total size, adopt the expected value from the task
                                                if expected > 0 && totalSize == 0 {
                                                    totalSize = expected
                                                    Task { @MainActor in
                                                        if let idx = self.datasetItems.firstIndex(where: { $0.id == id }) {
                                                            self.objectWillChange.send()
                                                            self.datasetItems[idx].expectedBytes = expected
                                                            if self.loggedDatasetExpected[id] != expected {
                                                                self.loggedDatasetExpected[id] = expected
                                                                self.logDetectedSize(kind: "Dataset", id: id, bytes: expected, source: "Content-Length")
                                                            }
                                                        }
                                                    }
                                                }
                                                let lastT = speedLastTime ?? now
                                                let dt = now.timeIntervalSince(lastT)
                                                guard dt >= 0.25 else { return }
                                                let raw = Double(written - lastBytes) / dt
                                                let instSpeed = max(0, min(raw, self.maxInstantaneousSpeed))
                                                speedLastTime = now
                                                lastBytes = written
                                                Task { @MainActor in
                                                    if let idx = self.datasetItems.firstIndex(where: { $0.id == id }) {
                                                        let previous = self.datasetItems[idx].speed
                                                        let alpha = self.speedEMAAlpha
                                                        let clipped = min(instSpeed, self.maxInstantaneousSpeed)
                                                        self.datasetItems[idx].speed = previous * (1 - alpha) + clipped * alpha
                                                        self.lastDatasetSpeedSampleAt[self.datasetItems[idx].id] = Date()
                                                    }
                                                }
                                            })
                                        break retryLoop
                                        } catch {
                                            // Ensure this Task remains non-throwing so it fits `Task<Void, Never>`.
                                            if Task.isCancelled {
                                                // Exit quietly on cancellation; overlay cleanup happens via cancel().
                                                await MainActor.run {
                                                    self.tasks[id] = nil
                                                    if self.allItems.isEmpty { self.showOverlay = false }
                                                }
                                                return
                                            }
                                            let errType = self.categorizeError(error)
                                            if errType.isRetryable {
                                                // Exponential backoff, then retry the same file.
                                                attempt += 1
                                                let delay = min(pow(2.0, Double(attempt)), 60)
                                                try? await Task.sleep(for: .seconds(delay))
                                                await self.waitForNetworkConnectivity()
                                                continue retryLoop
                                            } else {
                                                // Non-retryable: surface error and terminate the dataset task gracefully.
                                                await MainActor.run {
                                                    if let idx = self.datasetItems.firstIndex(where: { $0.id == id }) {
                                                        self.objectWillChange.send()
                                                        self.datasetItems[idx].error = errType
                                                        self.datasetItems[idx].speed = 0
                                                    }
                                                    self.tasks[id] = nil
                                                    if self.allItems.isEmpty { self.showOverlay = false }
                                                }
                                                return
                                            }
                                        }
                                        completedBytes += max(knownExpected, 0)
                                        if let idx = self.datasetItems.firstIndex(where: { $0.id == id }) {
                                                self.objectWillChange.send()
                                                self.datasetItems[idx].downloadedBytes = completedBytes
                                        }
                                        if totalSize == 0 { completedFiles += 1 }
                                }

                                await MainActor.run {
                                        if let idx = self.datasetItems.firstIndex(where: { $0.id == id }) {
                                                self.objectWillChange.send()
                                                self.datasetItems[idx].progress = 1
                                                self.datasetItems[idx].downloadedBytes = totalSize
                                                self.datasetItems[idx].speed = 0
                                                self.datasetItems[idx].completed = true
                                        }
                                        // Keep the item visible briefly to avoid flicker back to a button
                                        self.tasks[id] = nil
                                        Task { @MainActor in
                                                try? await Task.sleep(for: .seconds(3))
                                                self.objectWillChange.send()
                                                self.datasetItems.removeAll { $0.id == id }
                                                if self.allItems.isEmpty { self.showOverlay = false }
                                        }
                                }
                        }
                }
		
		tasks[id] = t
	}
	
	func startEmbedding(repoID: String) {
		let id = repoID
		if tasks[id] != nil { return }
		if FileManager.default.fileExists(atPath: EmbeddingModel.modelURL.path) {
			Task { await logger.log("[DownloadController] Embedding model already installed; skipping download request for \(repoID)") }
			NotificationCenter.default.post(name: .embeddingModelAvailabilityChanged, object: nil, userInfo: ["available": true])
			return
		}
		
		var item = EmbeddingItem(repoID: repoID)
		embeddingItems.append(item)
		showOverlay = true
		
		let t = Task { [weak self] in
			guard let self else { return }
			do {
				// Attempt to discover expected content length via HEAD/Range
				let remote = URL(string: "https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF/resolve/main/nomic-embed-text-v1.5.Q4_K_M.gguf?download=1")!
				let knownExpected = await self.fetchRemoteSize(remote)
				if knownExpected > 0 && self.loggedEmbedExpected[repoID] != knownExpected {
					self.loggedEmbedExpected[repoID] = knownExpected
					self.logDetectedSize(kind: "Embed", id: repoID, bytes: knownExpected, source: "HEAD")
				}
				// Record expected bytes for aggregation if known
				await MainActor.run {
					if let idx = self.embeddingItems.firstIndex(where: { $0.id == repoID }) {
						self.embeddingItems[idx].expectedBytes = max(knownExpected, 0)
					}
				}
                var completed: Int64 = 0
                // Ensure destination directory exists before moving
                try FileManager.default.createDirectory(at: EmbeddingModel.modelDir, withIntermediateDirectories: true)
                let dest = EmbeddingModel.modelURL
                var req = URLRequest(url: remote)
                req.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
                req.setValue("Noema/1.0 (+https://noema.app)", forHTTPHeaderField: "User-Agent")
                try await BackgroundDownloadManager.shared.download(
                    request: req,
                    to: dest,
                    expectedSize: knownExpected,
                    progress: { [weak self] prog in
                        guard let self else { return }
                        Task { @MainActor in
                            if let idx = self.embeddingItems.firstIndex(where: { $0.id == repoID }) {
                                let cur = Int64(Double(max(knownExpected, 0)) * min(prog, 0.999))
                                let total = max(knownExpected, 1)
                                self.embeddingItems[idx].progress = max(0, min(1, Double(cur) / Double(total)))
                            }
                        }
                    },
                    progressBytes: { [weak self] written, _ in
                        guard let self else { return }
                        // Keep speed optional for embed download UI; we don't show it, but we can later
                        _ = written
                    })
                UserDefaults.standard.set(true, forKey: "hasInstalledEmbedModel:\(dest.path)")
                NotificationCenter.default.post(name: .embeddingModelAvailabilityChanged, object: nil, userInfo: ["available": true])
                completed = knownExpected
				
				await MainActor.run {
					if let idx = self.embeddingItems.firstIndex(where: { $0.id == repoID }) {
						self.embeddingItems[idx].progress = 1
						self.embeddingItems[idx].speed = 0
						self.embeddingItems[idx].completed = true
						if self.embeddingItems[idx].expectedBytes == 0 { self.embeddingItems[idx].expectedBytes = completed }
					}
					// Keep the item visible briefly to avoid flicker back to a button
					self.tasks[id] = nil
					Task { @MainActor in
						try? await Task.sleep(for: .seconds(1.2))
						self.embeddingItems.removeAll()
						if self.allItems.isEmpty { self.showOverlay = false }
					}
				}
			} catch {
				await MainActor.run {
					if let idx = self.embeddingItems.firstIndex(where: { $0.id == repoID }) {
						self.embeddingItems[idx].error = .permanentError("Failed to download embedding model: \(error.localizedDescription)")
					}
					self.tasks[id] = nil
					if self.allItems.isEmpty { self.showOverlay = false }
				}
			}
		}
		
		tasks[id] = t
	}
	
	// HEAD size helper
	private func fetchRemoteSize(_ url: URL) async -> Int64 {
		var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
		var items = comps.queryItems ?? []
		if !items.contains(where: { $0.name == "download" }) {
			items.append(URLQueryItem(name: "download", value: "1"))
		}
		comps.queryItems = items
		var req = URLRequest(url: comps.url!)
		req.httpMethod = "HEAD"
		if let token = UserDefaults.standard.string(forKey: "huggingFaceToken"), !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
			req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		}
		do {
			if NetworkKillSwitch.isEnabled { throw URLError(.notConnectedToInternet) }
			NetworkKillSwitch.track(session: URLSession.shared)
			let (_, resp) = try await URLSession.shared.data(for: req)
			if let http = resp as? HTTPURLResponse {
				if let lenStr = http.value(forHTTPHeaderField: "Content-Length"), let len = Int64(lenStr), len > 0 { return len }
				if let range = http.value(forHTTPHeaderField: "Content-Range"), let total = range.split(separator: "/").last, let len = Int64(total) { return len }
				if http.expectedContentLength > 0 { return http.expectedContentLength }
			}
		} catch {}
		return 0
	}

	// Extract "owner/repo" from a Hugging Face URL if present
    private func huggingFaceRepoID(from url: URL) -> String? {
                guard let host = url.host, host.contains("huggingface.co") else { return nil }
                var parts = url.path.split(separator: "/").filter { !$0.isEmpty }.map(String.init)
                let prefixes: Set<String> = ["repos", "api", "models"]
                while parts.count > 2, let first = parts.first, prefixes.contains(first) {
                        parts.removeFirst()
                }
                guard parts.count >= 2 else { return nil }
                let owner = parts[0]
                let repo = parts[1]
                guard !owner.isEmpty && !repo.isEmpty else { return nil }
                return "\(owner)/\(repo)"
        }

    private func logDetectedSize(kind: String, id: String, bytes: Int64, source: String) {
        guard bytes > 0 else { return }
        let human = Self.byteFormatter.string(fromByteCount: bytes)
        Task { await logger.log("[Download][Size][\(kind)] id=\(id) size=\(human) (\(bytes)B) source=\(source)") }
    }

	func cancel(itemID: String) {
		tasks[itemID]?.cancel()
		tasks[itemID] = nil
		if let idx = items.firstIndex(where: { $0.id == itemID }) {
			let item = items.remove(at: idx)
			Task { await manager.cancel(modelID: item.detail.id, quantLabel: item.quant.label) }
			if let dest = item.mmprojDestination {
				BackgroundDownloadManager.shared.cancel(destination: dest)
			}
			// Aggressively clean up partial files for this download (main + projector)
			let base = InstalledModelsStore.baseDir(for: item.quant.format, modelID: item.detail.id)
			let mainTmp = base.appendingPathComponent("\(item.quant.label).download")
			let mainFinal = base.appendingPathComponent(item.quant.downloadURL.lastPathComponent)
			try? FileManager.default.removeItemIfExists(at: mainTmp)
			try? FileManager.default.removeItemIfExists(at: mainFinal)
			if let dest = item.mmprojDestination {
				let mmTmp = dest.deletingPathExtension().appendingPathExtension("download")
				try? FileManager.default.removeItemIfExists(at: dest)
				try? FileManager.default.removeItemIfExists(at: mmTmp)
			}
		}
		if let idx = leapItems.firstIndex(where: { $0.id == itemID }) {
			self.objectWillChange.send()
			leapItems.remove(at: idx)
			LeapBundleDownloader.shared.cancel(slug: itemID)
		}
		if let idx = datasetItems.firstIndex(where: { $0.id == itemID }) {
			datasetItems.remove(at: idx)
		}
		if let idx = embeddingItems.firstIndex(where: { $0.id == itemID }) {
			embeddingItems.remove(at: idx)
		}
		if allItems.isEmpty { showOverlay = false }
	}
	
	/// Called when user taps overlay
        func openList() {
                showPopup = true
        }

        func closeList() {
                showPopup = false
        }
	
	var overallProgress: Double {
		let supported: Set<String> = ["pdf", "epub", "txt", "md", "json", "jsonl", "csv", "tsv"]
		let bytesGGUF = items.reduce(0.0) {
			let counts = byteCounts(for: $1)
			return $0 + Double(counts.mainExpected) + Double(counts.mmExpected)
		}
                let bytesSLM  = leapItems.reduce(0.0) { acc, li in
                        let expected = li.expectedBytes > 0
                                ? li.expectedBytes
                                : (li.entry.sizeBytes > 0 ? li.entry.sizeBytes : 1)
                        return acc + Double(expected)
                }
                let bytesDS   = datasetItems.reduce(0.0) { res, item in
                        let expected = item.expectedBytes > 0 ? Double(item.expectedBytes) :
                                item.detail.files.filter { supported.contains($0.downloadURL.pathExtension.lowercased()) }
                                        .reduce(0.0) { $0 + Double($1.sizeBytes) }
                        return res + expected
                }
		// Include embedding model downloads in aggregation; fallback to weight=1 when expected unknown
		let bytesEMB  = embeddingItems.reduce(0.0) { res, item in
			let expected = item.expectedBytes > 0 ? Double(item.expectedBytes) : 1.0
			return res + expected
		}
		let total = bytesGGUF + bytesSLM + bytesDS + bytesEMB
		guard total > 0 else { return 0 }
		let completedGGUF = items.reduce(0.0) {
			let counts = byteCounts(for: $1)
			let expected = Double(counts.mainExpected + counts.mmExpected)
			return $0 + expected * $1.progress
		}
                let completedSLM  = leapItems.reduce(0.0) { acc, li in
                        let expected = li.expectedBytes > 0
                                ? li.expectedBytes
                                : (li.entry.sizeBytes > 0 ? li.entry.sizeBytes : 1)
                        return acc + Double(expected) * li.progress
                }
                let completedDS   = datasetItems.reduce(0.0) { res, item in
                        let expected = item.expectedBytes > 0 ? Double(item.expectedBytes) :
                                item.detail.files.filter { supported.contains($0.downloadURL.pathExtension.lowercased()) }
                                        .reduce(0.0) { $0 + Double($1.sizeBytes) }
                        let done = item.expectedBytes > 0 ? Double(item.downloadedBytes) : expected * item.progress
                        return res + done
                }
		let completedEMB = embeddingItems.reduce(0.0) { res, item in
			let expected = item.expectedBytes > 0 ? Double(item.expectedBytes) : 1.0
			return res + expected * item.progress
		}
		return (completedGGUF + completedSLM + completedDS + completedEMB) / total
	}
	
	var allItems: [Any] {
		return items as [Any] + leapItems as [Any] + datasetItems as [Any] + embeddingItems as [Any]
	}
	
	var allCompleted: Bool {
		!allItems.isEmpty && items.allSatisfy({ $0.completed }) && leapItems.allSatisfy({ $0.completed }) && datasetItems.allSatisfy({ $0.completed }) && embeddingItems.allSatisfy({ $0.completed })
	}
	
	// Aggregation for embedding progress (bytes)
	private var embedTotalBytes: Double = 0
	private var embedCompletedBytes: Double = 0

	private static func datasetBaseDir(for datasetID: String) -> URL {
		var url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
		url.appendPathComponent("LocalLLMDatasets", isDirectory: true)
		for comp in datasetID.split(separator: "/").map(String.init) {
			url.appendPathComponent(comp, isDirectory: true)
		}
        return url
        }
    }
#endif
