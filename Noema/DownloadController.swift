// DownloadController.swift
import Foundation
import SwiftUI
import Network

@MainActor
final class DownloadController: ObservableObject {
	struct Item: Identifiable, Equatable {
		let detail: ModelDetails
		let quant: QuantInfo
		var progress: Double = 0
		var speed: Double = 0
		var completed = false
		var error: DownloadError? = nil
		var retryCount: Int = 0
		// Track per-part progress for combined progress computation
		var mainProgress: Double = 0
		var mmprojProgress: Double = 0
		var mmprojSize: Int64 = 0

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
	private weak var modelManager: Noema.AppModelManager?
	private weak var datasetManager: DatasetManager?
	
	func configure(modelManager: Noema.AppModelManager, datasetManager: DatasetManager) {
		self.modelManager = modelManager
		self.datasetManager = datasetManager
	}
	
	private func key(for detail: ModelDetails, quant: QuantInfo) -> String {
		"\(detail.id)-\(quant.label)"
	}
	
	func start(detail: ModelDetails, quant: QuantInfo) {
		let id = key(for: detail, quant: quant)
		if tasks[id] != nil { return }

		var item = Item(detail: detail, quant: quant)
		items.append(item)
		showOverlay = true
		
		let t = Task { [weak self] in
			guard let self else { return }
			// For any GGUF model, if the repo offers an mmproj, download it alongside the main quant
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
				if let quantRepo = huggingFaceRepoID(from: quant.downloadURL) {
					repoCandidates.append(quantRepo)
				}
				if !repoCandidates.contains(detail.id) {
					repoCandidates.append(detail.id)
				}
				for repo in repoCandidates {
					if let proj = await self.discoverMMProj(repoId: repo) {
						let escapedRepo = repo.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repo
						let url = URL(string: "https://huggingface.co/\(escapedRepo)/resolve/main/\(proj.name)?download=1")!
						selected = (proj.name, url, proj.size)
						break
					}
				}
				await MainActor.run {
					if let idx = self.items.firstIndex(where: { $0.id == id }) {
						self.items[idx].mmprojSize = selected?.size ?? 0
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
				// If none offered, continue with main download
				if let sel = selected, sel.size > 0 {
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
							final class Delegate: NSObject, URLSessionDataDelegate {
								let handle: FileHandle
								var expected: Int64
								var bytes: Int64 = 0
								var lastBytes: Int64
								var lastTime: Date
								var lastProgress: Double = 0
								let onProgress: @Sendable (Double, Int64, Double) -> Void
								init(handle: FileHandle, expected: Int64, start: Date, onProgress: @escaping @Sendable (Double, Int64, Double) -> Void) {
									self.handle = handle
									self.expected = expected
									self.onProgress = onProgress
									self.lastTime = start
									self.lastBytes = 0
								}
								func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
									if expected <= 0 { expected = response.expectedContentLength }
									completionHandler(.allow)
								}
								func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
									try? handle.write(contentsOf: data)
									bytes += Int64(data.count)
									let now = Date()
									let prog = expected > 0 ? Double(bytes) / Double(expected) : 0
									if prog - lastProgress >= 0.01 || now.timeIntervalSince(lastTime) >= 0.3 {
										let speed = Double(bytes - lastBytes) / now.timeIntervalSince(lastTime)
										lastBytes = bytes
										lastTime = now
										lastProgress = prog
										onProgress(prog, bytes, speed)
									}
								}
								private var cont: CheckedContinuation<Void, Error>?
								func wait() async throws { try await withCheckedThrowingContinuation { self.cont = $0 } }
								func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
									try? handle.close()
									if let e = error { cont?.resume(throwing: e) } else { cont?.resume() }
								}
							}
							let start = Date()
							let delegate = Delegate(handle: handle, expected: sel.size, start: start) { prog, _, speed in
								Task { @MainActor in
									if let idx = self.items.firstIndex(where: { $0.id == id }) {
										self.items[idx].mmprojProgress = prog
										// Combine mmproj + main file progress by bytes
										let mmBytes = Double(self.items[idx].mmprojSize)
										let mainBytes = Double(self.items[idx].quant.sizeBytes)
										let denom = mmBytes + mainBytes
										let combined = denom > 0 ? ((mmBytes * prog) + (mainBytes * self.items[idx].mainProgress)) / denom : prog
										self.items[idx].progress = combined
										// Update instantaneous speed while mmproj downloads
										self.items[idx].speed = speed
									}
								}
							}
							let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
							NetworkKillSwitch.track(session: session)
							if startOffset > 0 { req.setValue("bytes=\(startOffset)-", forHTTPHeaderField: "Range") }
							let dataTask = session.dataTask(with: req)
							dataTask.resume()
							try await delegate.wait()
							// Validate GGUF magic to avoid saving HTML error pages
							if let fh = try? FileHandle(forReadingFrom: tmp) {
								defer { try? fh.close() }
								let magic = try fh.read(upToCount: 4) ?? Data()
								if magic != Data("GGUF".utf8) { throw URLError(.cannotParseResponse) }
							}
							                            												try FileManager.default.moveItemReplacing(at: mmprojDest, from: tmp)
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
                                    // Recompute combined progress (main could still be 0 here)
                                    let mmBytes = Double(self.items[idx].mmprojSize)
                                    let mainBytes = Double(self.items[idx].quant.sizeBytes)
                                    let denom = mmBytes + mainBytes
                                    let combined = denom > 0 ? ((mmBytes * 1) + (mainBytes * self.items[idx].mainProgress)) / denom : 1
                                    self.items[idx].progress = combined
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
					case .progress(let p, _, _, let speed):
						self.items[idx].mainProgress = p
						// Smooth out speed fluctuations using a simple
						// exponential moving average so the UI is less jittery
						let previous = self.items[idx].speed
						let factor = 0.3
						self.items[idx].speed = previous * (1 - factor) + speed * factor
						// Recompute combined progress
						let mmBytes = Double(self.items[idx].mmprojSize)
						let mainBytes = Double(self.items[idx].quant.sizeBytes)
						let denom = mmBytes + mainBytes
						let combined = denom > 0 ? ((mmBytes * self.items[idx].mmprojProgress) + (mainBytes * p)) / denom : p
						self.items[idx].progress = combined
					case .finished(let installed):
						self.items[idx].mainProgress = 1
						self.items[idx].progress = 1
						self.items[idx].speed = 0
						self.items[idx].completed = true
						self.items[idx].error = nil
						self.modelManager?.install(installed)
						// If a dataset was just downloaded via dataset flow, DatasetManager triggers indexing itself.
						self.tasks[id] = nil
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
						if self.allItems.isEmpty { self.showOverlay = false }
                                        case .paused(let p):
                                                self.items[idx].mainProgress = p
                                                self.items[idx].speed = 0
                                                self.items[idx].error = nil
                                                self.paused.insert(id)
                                                // Recompute combined progress
                                                let mmBytes = Double(self.items[idx].mmprojSize)
                                                let mainBytes = Double(self.items[idx].quant.sizeBytes)
                                                let denom = mmBytes + mainBytes
                                                let combined = denom > 0 ? ((mmBytes * self.items[idx].mmprojProgress) + (mainBytes * p)) / denom : p
                                                self.items[idx].progress = combined
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
								if self.allItems.isEmpty {
									self.showOverlay = false
								}
							}
						}
                                        case .networkError(let error, let progress):
                                                self.items[idx].mainProgress = progress
                                                self.items[idx].speed = 0
                                                self.items[idx].retryCount += 1
                                                // Recompute combined progress
                                                let mmBytes = Double(self.items[idx].mmprojSize)
                                                let mainBytes = Double(self.items[idx].quant.sizeBytes)
                                                let denom = mmBytes + mainBytes
                                                let combined = denom > 0 ? ((mmBytes * self.items[idx].mmprojProgress) + (mainBytes * progress)) / denom : progress
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

		var item = LeapItem(entry: entry)
		self.objectWillChange.send()
		leapItems.append(item)
		showOverlay = true
		
		let t = Task { [weak self] in
			guard let self else { return }
			for await event in LeapBundleDownloader.shared.download(entry) {
				await MainActor.run {
					guard let idx = self.leapItems.firstIndex(where: { $0.id == id }) else { return }
					switch event {
					case .started(let total):
						self.objectWillChange.send()
						if let t = total, t > 0 { self.leapItems[idx].expectedBytes = t }
					case .progress(let p, _, let expected, let speed):
						self.objectWillChange.send()
						self.leapItems[idx].progress = p
						let previous = self.leapItems[idx].speed
						let factor = 0.3
						self.leapItems[idx].speed = previous * (1 - factor) + speed * factor
						self.leapItems[idx].verifying = false
						if expected > 0 { self.leapItems[idx].expectedBytes = expected }
					case .finished(let installed):
						self.objectWillChange.send()
						self.leapItems[idx].progress = 1
						self.leapItems[idx].speed = 0
						self.leapItems[idx].completed = true
						self.leapItems[idx].verifying = false
						if self.leapItems[idx].expectedBytes <= 0 { self.leapItems[idx].expectedBytes = Int64(installed.sizeBytes) }
						self.modelManager?.install(installed)
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
                if upfrontTotal > 0 { item.expectedBytes = upfrontTotal }
                item.downloadedBytes = 0
                objectWillChange.send()
                datasetItems.append(item)
                showOverlay = true

                let t = Task { [weak self] in
                        guard let self else { return }
                        do {
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
                                let baseDir = Self.datasetBaseDir(for: id)
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
                                        var knownExpected: Int64 = file.sizeBytes
                                        if knownExpected <= 0 { knownExpected = await self.fetchRemoteSize(fileURL) }
                                        var lastBytes: Int64 = 0
                                        var lastTime = Date()
                                        let (tmp, resp) = try await URLSession.shared.downloadWithProgress(from: req.url!, expectedSize: knownExpected) { [weak self] frac, bytes in
                                                guard let self else { return }
                                                await MainActor.run {
                                                        if let idx = self.datasetItems.firstIndex(where: { $0.id == id }) {
                                                                self.objectWillChange.send()
                                                                if totalSize > 0 {
                                                                        let already = completedBytes
                                                                        let cur = bytes
                                                                        self.datasetItems[idx].downloadedBytes = already + cur
                                                                        let denom = Double(totalSize)
                                                                        let prog = denom > 0 ? Double(self.datasetItems[idx].downloadedBytes) / denom : 0
                                                                        self.datasetItems[idx].progress = max(0, min(1, prog))
                                                                } else {
                                                                        // Unknown total size (e.g., OTL). Use per-file equal-share fallback
                                                                        let prog = (Double(completedFiles) + frac) / Double(fileCount)
                                                                        self.datasetItems[idx].progress = max(0, min(1, prog))
                                                                        self.datasetItems[idx].downloadedBytes = completedBytes + bytes
                                                                }
                                                                let now = Date()
                                                                let deltaBytes = bytes - lastBytes
                                                                let deltaTime = now.timeIntervalSince(lastTime)
                                                                let instSpeed = deltaTime > 0 ? Double(deltaBytes) / deltaTime : 0
                                                                let previous = self.datasetItems[idx].speed
                                                                let factor = 0.3
                                                                self.datasetItems[idx].speed = previous * (1 - factor) + instSpeed * factor
                                                                lastBytes = bytes
                                                                lastTime = now
                                                        }
                                                }
                                        }
                                        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
                                        let dest = baseDir.appendingPathComponent(fileURL.lastPathComponent)
                                        try FileManager.default.moveItemReplacing(at: dest, from: tmp)
                                        completedBytes += knownExpected
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
                        } catch {
                                await MainActor.run {
                                        if let idx = self.datasetItems.firstIndex(where: { $0.id == id }) {
                                                self.objectWillChange.send()
                                                self.datasetItems[idx].error = .permanentError("Failed to download dataset: \(error.localizedDescription)")
                                        }
                                        self.tasks[id] = nil
                                        if self.allItems.isEmpty { self.showOverlay = false }
                                }
                        }
                }
		
		tasks[id] = t
	}
	
	func startEmbedding(repoID: String) {
		let id = repoID
		if tasks[id] != nil { return }
		
		var item = EmbeddingItem(repoID: repoID)
		embeddingItems.append(item)
		showOverlay = true
		
		let t = Task { [weak self] in
			guard let self else { return }
			do {
				// Attempt to discover expected content length via HEAD/Range
				let remote = URL(string: "https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF/resolve/main/nomic-embed-text-v1.5.Q4_K_M.gguf?download=1")!
				let knownExpected = await self.fetchRemoteSize(remote)
				// Record expected bytes for aggregation if known
				await MainActor.run {
					if let idx = self.embeddingItems.firstIndex(where: { $0.id == repoID }) {
						self.embeddingItems[idx].expectedBytes = max(knownExpected, 0)
					}
				}
                                var completed: Int64 = 0
                                let (tmp, resp) = try await URLSession.shared.downloadWithProgress(from: remote, expectedSize: knownExpected) { [weak self] prog, _ in
                                        guard let self else { return }
                                        await MainActor.run {
                                                if let idx = self.embeddingItems.firstIndex(where: { $0.id == repoID }) {
                                                        let cur = Int64(Double(knownExpected) * prog)
                                                        let total = max(knownExpected, 1)
                                                        self.embeddingItems[idx].progress = max(0, min(1, Double(cur) / Double(total)))
                                                }
                                        }
                                }
                                guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
                                // Ensure destination directory exists before moving
                                try FileManager.default.createDirectory(at: EmbeddingModel.modelDir, withIntermediateDirectories: true)
				let dest = EmbeddingModel.modelURL
				try FileManager.default.moveItemReplacing(at: dest, from: tmp)
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

	// Query HF API to find a projector file in the repo, if any
	private func discoverMMProj(repoId: String) async -> (name: String, size: Int64)? {
		let escaped = repoId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repoId
		guard let url = URL(string: "https://huggingface.co/api/models/\(escaped)?full=1") else { return nil }
		do {
			let token = UserDefaults.standard.string(forKey: "huggingFaceToken")
			let (data, resp) = try await HFHubRequestManager.shared.data(for: url,
																							 token: token,
																							 accept: "application/json",
																							 timeout: 10)
			guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
			guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
					let siblings = root["siblings"] as? [[String: Any]] else { return nil }
			// Known projector name patterns
			let patterns = ["mmproj", "projector", "image_proj"]
			for file in siblings {
				guard let fname = file["rfilename"] as? String else { continue }
				let lower = fname.lowercased()
				if lower.hasSuffix(".gguf") && patterns.contains(where: { lower.contains($0) }) {
					// Prefer LFS size if present
					var size: Int64 = 0
					if let lfs = file["lfs"] as? [String: Any], let s = lfs["size"] as? Int { size = Int64(s) }
					if size == 0, let sAny = file["size"] as? Int { size = Int64(sAny) }
					// If size still unknown, make a HEAD call to confirm; otherwise accept if > 0
					if size == 0 {
						if let headURL = URL(string: "https://huggingface.co/\(escaped)/resolve/main/\(fname)?download=1") {
							let head = await fetchRemoteSize(headURL)
							if head > 0 { size = head }
						}
					}
					if size > 0 { return (name: fname, size: size) }
				}
			}
		} catch {
			return nil
		}
		return nil
	}
	
	func cancel(itemID: String) {
		tasks[itemID]?.cancel()
		tasks[itemID] = nil
		if let idx = items.firstIndex(where: { $0.id == itemID }) {
			let item = items.remove(at: idx)
			Task { await manager.cancel(modelID: item.detail.id, quantLabel: item.quant.label) }
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
	
	var overallProgress: Double {
		let supported: Set<String> = ["pdf", "epub", "txt", "md", "json", "jsonl", "csv", "tsv"]
		let bytesGGUF = items.reduce(0.0) { $0 + Double($1.quant.sizeBytes) + Double($1.mmprojSize) }
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
		let completedGGUF = items.reduce(0.0) { $0 + (Double($1.quant.sizeBytes) + Double($1.mmprojSize)) * $1.progress }
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
