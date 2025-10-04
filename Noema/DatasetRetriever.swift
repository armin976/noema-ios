// DatasetRetriever.swift
import Foundation
#if canImport(PDFKit)
import PDFKit
#endif

/// Handles building and querying simple embedding indexes for datasets.
actor DatasetRetriever {
    static let shared = DatasetRetriever()

    private struct Chunk: Codable {
        let text: String
        let vector: [Float]
        /// Optional source string for citation display (e.g., "file.pdf #p12" or "notes.txt")
        let source: String?
    }
    private var cache: [String: [Chunk]] = [:]

    /// Purges any in-memory and on-disk embeddings for a dataset ID
    func purge(datasetID: String) {
        cache[datasetID] = nil
        // Best-effort on-disk cleanup in case the dataset folder still exists
        var base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        base.appendPathComponent("LocalLLMDatasets", isDirectory: true)
        for comp in datasetID.split(separator: "/").map(String.init) {
            base.appendPathComponent(comp, isDirectory: true)
        }
        let vectors = base.appendingPathComponent("vectors.json")
        try? FileManager.default.removeItem(at: vectors)
    }

    /// Returns the cached chunks for a dataset, computing them if needed.
    private func chunks(
        for dataset: LocalDataset,
        progress: (@MainActor @Sendable (DatasetProcessingStatus) -> Void)? = nil
    ) async throws -> [Chunk] {
        if let cached = cache[dataset.datasetID] { return cached }
        let file = dataset.url.appendingPathComponent("vectors.json")
        if let data = try? Data(contentsOf: file),
           let decoded = try? JSONDecoder().decode([Chunk].self, from: data) {
            cache[dataset.datasetID] = decoded
            return decoded
        }
        
        // Embedding model will be loaded on-demand during first embedFromText call
        Task { await logger.log("[RAG] Creating embeddings for dataset on-demand: \(dataset.datasetID)") }
        
        // Prefer pre-extracted compact text if available so we avoid re-parsing large PDFs
        let compactURL = dataset.url.appendingPathComponent("extracted.compact.txt")
        if let data = try? Data(contentsOf: compactURL),
           let str = String(data: data, encoding: .utf8) {
            let result = try await embedFromText(str, datasetID: dataset.datasetID) { frac, phase in
                if let progress {
                    Task { @MainActor in
                        progress(DatasetProcessingStatus(stage: .embedding, progress: frac, message: phase, etaSeconds: nil))
                    }
                }
            }
            cache[dataset.datasetID] = result
            if let out = try? JSONEncoder().encode(result) { try? out.write(to: file) }
            return result
        }

        // If no compact text exists, try to create it first
        let extractedURL = dataset.url.appendingPathComponent("extracted.txt")
        if !FileManager.default.fileExists(atPath: extractedURL.path) {
            // Extract text from dataset files first
            Task { await logger.log("[RAG] No extracted text found, extracting from dataset files: \(dataset.datasetID)") }
            await prepare(dataset: dataset, progress: nil)
        }
        
        // Now try again with the newly extracted compact text
        if let data = try? Data(contentsOf: compactURL),
           let str = String(data: data, encoding: .utf8) {
            let result = try await embedFromText(str, datasetID: dataset.datasetID) { frac, phase in
                if let progress {
                    Task { @MainActor in
                        progress(DatasetProcessingStatus(stage: .embedding, progress: frac, message: phase, etaSeconds: nil))
                    }
                }
            }
            cache[dataset.datasetID] = result
            if let out = try? JSONEncoder().encode(result) { try? out.write(to: file) }
            return result
        }

        var result: [Chunk] = []
        let fm = FileManager.default
        // Collect eligible file URLs synchronously so we don't hold the enumerator
        // across suspension points when computing embeddings.
        var urls: [URL] = []
        if let enumerator = fm.enumerator(at: dataset.url, includingPropertiesForKeys: [.isRegularFileKey]) {
            while let url = enumerator.nextObject() as? URL {
                let ext = url.pathExtension.lowercased()
                guard ["txt", "md", "json", "jsonl", "csv", "tsv", "pdf", "epub"].contains(ext) else { continue }
                urls.append(url)
            }
        }
        for url in urls {
            if Task.isCancelled { throw CancellationError() }
            let ext = url.pathExtension.lowercased()
#if canImport(PDFKit)
            if ext == "pdf" {
                if let doc = PDFKit.PDFDocument(url: url) {
                    var combined = ""
                    for i in 0..<doc.pageCount {
                        if let page = doc.page(at: i), let text = page.string {
                            combined += text + "\n"
                        }
                    }
                    let str = combined
                    // Treat like a text document and chunk by paragraphs
                    var paragraph = ""
                    @Sendable func shouldKeepParagraph(_ s: String) -> Bool {
                        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.count < 40 { return false }
                        // Filter obvious table-of-contents dot leaders and page numbers
                        let dotLeaders = trimmed.contains(" . . ") || trimmed.contains("......") || trimmed.contains(" · ")
                        let manyDots = trimmed.filter { $0 == "." }.count
                        let manyDigits = trimmed.filter { $0.isNumber }.count
                        if dotLeaders || manyDots > max(3, trimmed.count / 10) || manyDigits > max(12, trimmed.count / 3) {
                            return false
                        }
                        return true
                    }
                    func chunk(for paragraph: String) async -> Chunk? {
                        let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty, shouldKeepParagraph(trimmed) else { return nil }
                        let vec = await EmbeddingModel.shared.embedDocument(trimmed)
                        
                        // Add validation for embedding vector
                        guard !vec.isEmpty, vec.allSatisfy({ $0.isFinite }) else {
                            await logger.log("[RAG] ❌ Invalid or empty embedding returned for PDF text, skipping chunk.")
                            return nil
                        }
                        
                        return Chunk(text: trimmed, vector: vec, source: url.lastPathComponent)
                    }
                    for line in str.components(separatedBy: .newlines) {
                        if Task.isCancelled { throw CancellationError() }
                        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if t.isEmpty {
                            if let c = await chunk(for: paragraph) { result.append(c) }
                            paragraph = ""
                        } else {
                            paragraph += (paragraph.isEmpty ? "" : " ") + t
                        }
                    }
                    if let c = await chunk(for: paragraph) { result.append(c) }
                }
                continue
            }
#endif
            if ext == "epub" {
                let str = EPUBTextExtractor.extractText(from: url)
                var paragraph = ""
                @Sendable func shouldKeepParagraph(_ s: String) -> Bool {
                    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.count < 40 { return false }
                    let manyDots = trimmed.filter { $0 == "." }.count
                    let manyDigits = trimmed.filter { $0.isNumber }.count
                    if manyDots > max(3, trimmed.count / 10) || manyDigits > max(12, trimmed.count / 3) { return false }
                    return true
                }
                func chunk(for paragraph: String) async -> Chunk? {
                    let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, shouldKeepParagraph(trimmed) else { return nil }
                    let vec = await EmbeddingModel.shared.embedDocument(trimmed)
                    
                    // Add validation for embedding vector
                    guard !vec.isEmpty, vec.allSatisfy({ $0.isFinite }) else {
                        await logger.log("[RAG] ❌ Invalid or empty embedding returned for EPUB text, skipping chunk.")
                        return nil
                    }
                    
                    return Chunk(text: trimmed, vector: vec, source: url.lastPathComponent)
                }
                for line in str.components(separatedBy: .newlines) {
                    if Task.isCancelled { throw CancellationError() }
                    let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if t.isEmpty {
                        if let c = await chunk(for: paragraph) { result.append(c) }
                        paragraph = ""
                    } else {
                        paragraph += (paragraph.isEmpty ? "" : " ") + t
                    }
                }
                if let c = await chunk(for: paragraph) { result.append(c) }
                continue
            }
            if let str = try? String(contentsOf: url) {
                if ["txt", "md"].contains(ext) {
                    // Combine consecutive non-empty lines into paragraphs so
                    // retrieval preserves more context for prose documents.
                    var paragraph = ""
                    @Sendable func shouldKeepParagraph(_ s: String) -> Bool {
                        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                        return trimmed.count >= 40
                    }
                    func chunk(for paragraph: String) async -> Chunk? {
                        let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty, shouldKeepParagraph(trimmed) else { return nil }
                        let vec = await EmbeddingModel.shared.embedDocument(trimmed)
                        
                        // Add validation for embedding vector
                        guard !vec.isEmpty, vec.allSatisfy({ $0.isFinite }) else {
                            await logger.log("[RAG] ❌ Invalid or empty embedding returned for text file, skipping chunk.")
                            return nil
                        }
                        
                        return Chunk(text: trimmed, vector: vec, source: url.lastPathComponent)
                    }
                    for line in str.components(separatedBy: .newlines) {
                        if Task.isCancelled { throw CancellationError() }
                        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if t.isEmpty {
                            if let c = await chunk(for: paragraph) { result.append(c) }
                            paragraph = ""
                        } else {
                            paragraph += (paragraph.isEmpty ? "" : " ") + t
                        }
                    }
                    if let c = await chunk(for: paragraph) { result.append(c) }
                } else {
                    for line in str.components(separatedBy: .newlines) {
                        if Task.isCancelled { throw CancellationError() }
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { continue }
                        let vec = await EmbeddingModel.shared.embedDocument(trimmed)
                        
                        // Add validation for embedding vector
                        guard !vec.isEmpty, vec.allSatisfy({ $0.isFinite }) else {
                            await logger.log("[RAG] ❌ Invalid or empty embedding returned for \(url.pathExtension) file, skipping line.")
                            continue
                        }
                        
                        result.append(Chunk(text: trimmed, vector: vec, source: url.lastPathComponent))
                    }
                }
            }
        }
        cache[dataset.datasetID] = result
        if let data = try? JSONEncoder().encode(result) {
            try? data.write(to: file)
        }
        return result
    }

    /// Precomputes text extraction and compression for the dataset, and optionally proceeds to embeddings.
    /// When `pauseBeforeEmbedding` is true, this function will stop after compression and emit an `.embedding`
    /// status with 0% progress, leaving it to the caller to trigger the embedding step via `embedPrepared`.
    func prepare(
        dataset: LocalDataset,
        pauseBeforeEmbedding: Bool = false,
        progress: (@MainActor @Sendable (DatasetProcessingStatus) -> Void)? = nil
    ) async {
        // Persist indexing flag so tool gate can disable web search while indexing runs
        UserDefaults.standard.set(dataset.datasetID, forKey: "indexingDatasetIDPersisted")
        // Only extract and compress text during indexing - no embedding model loading
        Task { await logger.log("[RAG] prepare.start dataset=\(dataset.datasetID)") }
        let dir = dataset.url
        let extractedURL = dir.appendingPathComponent("extracted.txt")
        let compactURL = dir.appendingPathComponent("extracted.compact.txt")
        let vectorsURL = dir.appendingPathComponent("vectors.json")

        // If vectors already exist, we're fully done.
        if FileManager.default.fileExists(atPath: vectorsURL.path) {
            Task { await logger.log("[RAG] vectors.exist path=\(vectorsURL.lastPathComponent) - indexing complete") }
            if let progress { await progress(DatasetProcessingStatus(stage: .completed, progress: 1.0, message: "Ready for use", etaSeconds: 0)) }
            return
        }

        do {
            if !FileManager.default.fileExists(atPath: compactURL.path) {
                Task { await logger.log("[RAG] extract.begin") }
                if let progress { await progress(DatasetProcessingStatus(stage: .extracting, progress: 0.0, message: "Extracting text from files (images ignored)", etaSeconds: nil)) }
                let t0 = Date()
                let extracted = try await extractPlainText(from: dataset) { frac in
                    Task { @MainActor in
                        let dt = Date().timeIntervalSince(t0)
                        let eta = frac > 0 ? dt * (1.0 / frac - 1.0) : nil
                        progress?(DatasetProcessingStatus(stage: .extracting, progress: frac, message: "Extracting text from files (images ignored)", etaSeconds: eta))
                    }
                }
                try? extracted.data(using: .utf8)?.write(to: extractedURL)
                Task { await logger.log("[RAG] extract.done size=\(extracted.count)B dt=\(String(format: "%.2f", Date().timeIntervalSince(t0)))s") }

                if let progress { await progress(DatasetProcessingStatus(stage: .compressing, progress: 0.0, message: "Normalizing whitespace and merging paragraphs", etaSeconds: nil)) }
                let c0 = Date()
                let compact = compactText(extracted) { frac in
                    Task { @MainActor in
                        let dt = Date().timeIntervalSince(c0)
                        let eta = frac > 0 ? dt * (1.0 / frac - 1.0) : nil
                        progress?(DatasetProcessingStatus(stage: .compressing, progress: frac, message: "Normalizing whitespace and merging paragraphs", etaSeconds: eta))
                    }
                }
                try? compact.data(using: .utf8)?.write(to: compactURL)
                Task { await logger.log("[RAG] compress.done size=\(compact.count)B dt=\(String(format: "%.2f", Date().timeIntervalSince(c0)))s") }
            }

            // If caller asked to pause, emit an embedding gate status; otherwise continue to embeddings.
            if pauseBeforeEmbedding {
                if let progress { await progress(DatasetProcessingStatus(stage: .embedding, progress: 0.0, message: "Ready to compute embeddings. Tap Confirm to start. For best performance, plug in your phone.", etaSeconds: nil)) }
                Task { await logger.log("[RAG] prepare.paused - awaiting user confirmation for embeddings") }
                return
            } else {
                // Proceed to embedding immediately so indexing completes in one go
                try await embedPrepared(dataset: dataset, progress: progress)
            }
        } catch {
            Task { await logger.log("[RAG] ❌ prepare.failed error=\(error.localizedDescription)") }
            if let progress {
                if error is CancellationError {
                    await progress(DatasetProcessingStatus(stage: .failed, progress: 0.0, message: "Stopped", etaSeconds: nil))
                } else {
                    await progress(DatasetProcessingStatus(stage: .failed, progress: 0.0, message: "Failed", etaSeconds: nil))
                }
            }
        }
        // Clear indexing flag on completion or error
        UserDefaults.standard.set("", forKey: "indexingDatasetIDPersisted")
    }

    /// Performs the embedding step assuming extraction and compression have completed.
    /// Writes vectors to disk and reports progress via the provided closure.
    func embedPrepared(
        dataset: LocalDataset,
        progress: (@MainActor @Sendable (DatasetProcessingStatus) -> Void)? = nil
    ) async throws {
        let dir = dataset.url
        let extractedURL = dir.appendingPathComponent("extracted.txt")
        let compactURL = dir.appendingPathComponent("extracted.compact.txt")
        let vectorsURL = dir.appendingPathComponent("vectors.json")

        // Initial warmup phase so the user sees progress while the embedding model loads kernels.
        let warmUpFraction = 0.1
        if let progress {
            await progress(DatasetProcessingStatus(stage: .embedding, progress: 0.0, message: "Warming up embedding model…", etaSeconds: nil))
        }
        // Emit a slowly increasing progress while warm up runs to avoid a frozen bar
        let warmupTicker = Task.detached(priority: .utility) { [progress] in
            var p: Double = 0.0
            while !Task.isCancelled && p < warmUpFraction {
                p += warmUpFraction / 10.0
                if let progress {
                    await MainActor.run {
                        progress(DatasetProcessingStatus(stage: .embedding, progress: p, message: "Warming up embedding model…", etaSeconds: nil))
                    }
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        defer { warmupTicker.cancel() }
        await EmbeddingModel.shared.warmUp()
        if Task.isCancelled { throw CancellationError() }

        let text: String
        if let s = try? String(contentsOf: compactURL) {
            text = s
        } else if let s = try? String(contentsOf: extractedURL) {
            text = s
        } else {
            text = await fetchAllContent(for: dataset)
        }
        if let progress {
            await progress(DatasetProcessingStatus(stage: .embedding, progress: warmUpFraction, message: "Preparing chunks", etaSeconds: nil))
        }
        let textToEmbed = text
        if Task.isCancelled { throw CancellationError() }
        let startTime = Date()
        let finalChunks = try await embedFromText(textToEmbed) { frac, phase in
            Task { @MainActor in
                // Rough ETA estimate using elapsed time and progress slope
                let elapsed = Date().timeIntervalSince(startTime)
                let eta: Double? = (frac > 0.01) ? max(0, elapsed * (1.0 / frac - 1.0)) : nil
                let adjusted = warmUpFraction + frac * (1 - warmUpFraction)
                progress?(DatasetProcessingStatus(stage: .embedding, progress: adjusted, message: phase, etaSeconds: eta))
            }
        }
        if Task.isCancelled { throw CancellationError() }
        if let data = try? JSONEncoder().encode(finalChunks) {
            try? data.write(to: vectorsURL)
        }
        if Task.isCancelled { throw CancellationError() }
        Task { await logger.log("[RAG] embedPrepared.done - embeddings complete") }
        // After finishing embeddings, if no other part of the app needs the
        // embedder, unload it to free CPU/RAM. We only unload when there are
        // zero active operations to avoid races with concurrent embeddings.
        Task.detached {
            // small delay to allow any immediate follow-up operations to start
            try? await Task.sleep(nanoseconds: 200_000_000)
            if await EmbeddingModel.shared.activeOperationsCount == 0 {
                await EmbeddingModel.shared.unload()
            }
        }
        if Task.isCancelled { throw CancellationError() }
        if let progress { await progress(DatasetProcessingStatus(stage: .completed, progress: 1.0, message: "Ready for use", etaSeconds: 0)) }
    }

    // MARK: - Pipeline helpers

    private func extractPlainText(from dataset: LocalDataset, onProgress: @escaping (Double) -> Void) async throws -> String {
        var parts: [String] = []
        let fm = FileManager.default
        var pdfs: [URL] = []
        var epubs: [URL] = []
        var textFiles: [URL] = []
        if let enumerator = fm.enumerator(at: dataset.url, includingPropertiesForKeys: [.isRegularFileKey]) {
            while let url = enumerator.nextObject() as? URL {
                let ext = url.pathExtension.lowercased()
                guard ["txt", "md", "json", "jsonl", "csv", "tsv", "pdf", "epub"].contains(ext) else { continue }
                if ext == "pdf" { pdfs.append(url) }
                else if ext == "epub" { epubs.append(url) }
                else { textFiles.append(url) }
            }
        }
        #if canImport(PDFKit)
        var totalPages = 0
        for u in pdfs { if let doc = PDFKit.PDFDocument(url: u) { totalPages += doc.pageCount } }
        let totalEPUBUnits = epubs.reduce(0) { $0 + EPUBTextExtractor.countHTMLUnits(in: $1) }
        let denomUnits = max(totalPages + totalEPUBUnits, 1)
        var processed = 0
        for u in pdfs {
            if Task.isCancelled { break }
            if let doc = PDFKit.PDFDocument(url: u) {
                var combined = ""
                for i in 0..<doc.pageCount {
                    if Task.isCancelled { break }
                    if let page = doc.page(at: i), let text = page.string { combined += text + "\n" }
                    processed += 1
                    onProgress(min(0.95, Double(processed) / Double(denomUnits)))
                }
                parts.append(combined)
            }
        }
        #endif
        // Process EPUBs
        for u in epubs {
            if Task.isCancelled { break }
            let text = EPUBTextExtractor.extractText(from: u) { done, _ in
                processed += 1
                onProgress(min(0.95, Double(processed) / Double(denomUnits)))
            }
            parts.append(text)
        }
        for u in textFiles {
            if Task.isCancelled { break }
            if let str = try? String(contentsOf: u) { parts.append(str) }
        }
        onProgress(1.0)
        return parts.joined(separator: "\n\n")
    }

    private func compactText(_ text: String, onProgress: (Double) -> Void) -> String {
        let lines = text.components(separatedBy: .newlines)
        var out: [String] = []
        out.reserveCapacity(lines.count)
        var lastBlank = false
        let total = max(lines.count, 1)
        for (idx, line) in lines.enumerated() {
            var t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty {
                if !lastBlank { out.append("") }
                lastBlank = true
            } else {
                t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                out.append(t)
                lastBlank = false
            }
            if idx % 200 == 0 { onProgress(Double(idx + 1) / Double(total)) }
        }
        onProgress(1.0)
        return out.joined(separator: "\n")
    }

    private func embedFromText(_ text: String, datasetID: String? = nil, onProgress: @escaping @Sendable (Double, String) -> Void) async throws -> [Chunk] {
        // Chunk by token cap without embedding per chunk; batch-embed at the end.
        var chunks: [String] = []
        var buffer = ""
        let lines = text.components(separatedBy: .newlines)
        let total = max(lines.count, 1)
        var lastProgressEmit = Date(timeIntervalSince1970: 0)
        let maxTokensPerChunk = 1200
        Task.detached { await logger.log("[RAG] Using maxTokensPerChunk=\(maxTokensPerChunk) for chunking") }

        func splitLongText(_ s: String, maxChars: Int) -> [String] {
            var out: [String] = []
            var remaining = s
            while !remaining.isEmpty {
                if remaining.count <= maxChars { out.append(remaining); break }
                // Try to split on the last sentence boundary or space before the limit
                let idx = remaining.index(remaining.startIndex, offsetBy: maxChars)
                var splitIndex = remaining[..<idx].lastIndex(of: "\n")
                    ?? remaining[..<idx].lastIndex(of: ".")
                    ?? remaining[..<idx].lastIndex(of: " ")
                if splitIndex == nil { splitIndex = idx }
                let part = String(remaining[..<splitIndex!]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !part.isEmpty { out.append(part) }
                remaining = String(remaining[splitIndex!..<remaining.endIndex])
                remaining = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return out
        }

        func flushBuffer() {
            let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                // Ensure we don't emit chunks that exceed the embedder's character limit
                let maxCharsPerChunk = 8000
                if trimmed.count <= maxCharsPerChunk {
                    chunks.append(trimmed)
                } else {
                    let parts = splitLongText(trimmed, maxChars: maxCharsPerChunk)
                    for p in parts { chunks.append(p) }
                }
            }
            buffer = ""
        }

        for (idx, line) in lines.enumerated() {
            if Task.isCancelled { throw CancellationError() }
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty {
                flushBuffer()
            } else {
                let prospective = buffer.isEmpty ? t : buffer + " " + t
                let tok = await EmbeddingModel.shared.countTokens(prospective)
                if tok > maxTokensPerChunk {
                    flushBuffer()
                    buffer = t
                } else {
                    buffer = prospective
                }
            }
            if idx % 50 == 0 {
                let now = Date()
                let frac = Double(idx + 1) / Double(total)
                onProgress(frac * 0.5, "Preparing chunks") // first half for chunking
                if now.timeIntervalSince(lastProgressEmit) > 1.0 {
                    lastProgressEmit = now
                    Task { await logger.log(String(format: "[RAG] embed.chunk %.0f%%", frac * 100)) }
                }
            }
        }
        flushBuffer()
        // Token-safety pass: ensure no chunk exceeds token cap; split by tokens when needed
        let tokenSafetyChunksCount = chunks.count
        let tokenSafetyMaxTokens = maxTokensPerChunk
        Task.detached { await logger.log("[RAG] token_safety_pass start chunks=\(tokenSafetyChunksCount) maxTokens=\(tokenSafetyMaxTokens)") }
        func splitLongByTokens(_ s: String, maxTokens: Int) async -> [String] {
            var remaining = s.trimmingCharacters(in: .whitespacesAndNewlines)
            var out: [String] = []
            while !remaining.isEmpty {
                let totalTokens = await EmbeddingModel.shared.countTokens(remaining)
                if totalTokens <= maxTokens { out.append(remaining); break }
                // Binary-search for largest prefix within token limit
                var low = 0
                var high = remaining.count
                var best = 0
                while low < high {
                    let mid = (low + high) / 2
                    let idx = remaining.index(remaining.startIndex, offsetBy: mid)
                    let prefix = String(remaining[..<idx])
                    let t = await EmbeddingModel.shared.countTokens(prefix)
                    if t <= maxTokens { best = mid; low = mid + 1 } else { high = mid }
                }
                if best == 0 {
                    // Fallback to char-based split
                    let parts = splitLongText(remaining, maxChars: 4000)
                    if parts.isEmpty { break }
                    out.append(parts[0])
                    remaining = parts.dropFirst().joined(separator: " ")
                    continue
                }
                let splitIdx = remaining.index(remaining.startIndex, offsetBy: best)
                let part = String(remaining[..<splitIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !part.isEmpty { out.append(part) }
                remaining = String(remaining[splitIdx...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return out
        }

        var tokenSafeChunks: [String] = []
        for c in chunks {
            if Task.isCancelled { throw CancellationError() }
            let tok = await EmbeddingModel.shared.countTokens(c)
            if tok <= maxTokensPerChunk {
                tokenSafeChunks.append(c)
            } else {
                Task.detached { await logger.log("[RAG] Chunk too large (\(tok) tokens), splitting by tokens") }
                let parts = await splitLongByTokens(c, maxTokens: maxTokensPerChunk)
                for p in parts {
                    tokenSafeChunks.append(p)
                    Task.detached {
                        let tcount = await EmbeddingModel.shared.countTokens(p)
                        await logger.log("[RAG] Added split part chars=\(p.count) tokens=\(tcount)")
                    }
                }
            }
        }
        chunks = tokenSafeChunks
        // Ensure we show an immediate hand-off to embedding phase at 50%
        onProgress(0.50, "Embedding")

        // Batch embed the prepared chunks, streaming per-item progress to UI
        var batched: [Chunk] = []
        if !chunks.isEmpty {
            let batchSize = 8
            var produced = 0
            let totalCount = chunks.count
            for i in stride(from: 0, to: chunks.count, by: batchSize) {
                if Task.isCancelled { throw CancellationError() }
                let j = min(i + batchSize, chunks.count)
                let slice = Array(chunks[i..<j])
                // Stream progress within the batch so UI updates at each item completion
                let baseProduced = produced
                let vecs = await EmbeddingModel.shared.embedDocumentsWithProgress(slice) { done, _ in
                    let overallDone = baseProduced + done
                    let frac = Double(overallDone) / Double(totalCount)
                    onProgress(0.5 + frac * 0.5, "Embedding")
                }
                if vecs.count == slice.count {
                    for (t, v) in zip(slice, vecs) {
                        if !v.isEmpty && v.allSatisfy({ $0.isFinite && !$0.isNaN }) {
                            batched.append(Chunk(text: t, vector: v, source: nil))
                        } else {
                            Task { await logger.log("[RAG] ⚠️ Skipping invalid/empty vector for a batch item") }
                            let ds = datasetID ?? "<unknown>"
                            Task { await writeEmbeddingFailureBackup(dataset: ds, source: nil, text: t, reason: "invalid_batch_vector") }
                        }
                    }
                } else {
                    // Fallback per-item if batch failed or mismatched
                    for t in slice {
                        let v = await EmbeddingModel.shared.embedDocument(t)
                        if !v.isEmpty && v.allSatisfy({ $0.isFinite && !$0.isNaN }) {
                            batched.append(Chunk(text: t, vector: v, source: nil))
                        } else {
                            let ds = datasetID ?? "<unknown>"
                            Task { await writeEmbeddingFailureBackup(dataset: ds, source: nil, text: t, reason: "fallback_failed") }
                        }
                    }
                }
                produced += (j - i)
                let frac = Double(produced) / Double(totalCount)
                onProgress(0.5 + frac * 0.5, "Embedding")
                Task { await logger.log(String(format: "[RAG] embed.progress %.0f%%", (0.5 + frac * 0.5) * 100)) }
            }
        }
        onProgress(1.0, "Embedding complete")
        return batched
    }

    /// Write a compact backup of a failed chunk embedding to disk for inspection.
    private func writeEmbeddingFailureBackup(dataset: String, source: String?, text: String, reason: String) async {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var dir = docs.appendingPathComponent("EmbeddingFailures", isDirectory: true)
        dir.appendPathComponent(dataset, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let formatter = ISO8601DateFormatter()
        let ts = formatter.string(from: Date())
        let safeReason = reason.replacingOccurrences(of: "\\s+", with: "_", options: .regularExpression)
        let filename = "fail_\(ts)_\(safeReason).txt"
        let fileURL = dir.appendingPathComponent(filename)
        let cap = 16_000
        let trimmed = String(text.prefix(cap))
        var content = "reason: \(reason)\nsource: \(source ?? "<unknown>")\ndataset: \(dataset)\n\n"
        content += trimmed
        do {
            try content.data(using: .utf8)?.write(to: fileURL)
            await logger.log("[RAG] Wrote embedding failure backup: \(fileURL.path)")
        } catch {
            await logger.log("[RAG] ⚠️ Failed to write embedding backup: \(error.localizedDescription)")
        }
    }

    /// Estimates how many tokens the full dataset would occupy when inserted
    /// into the prompt. Uses the embedding model's tokenizer for counting.
    func estimateTokens(in dataset: LocalDataset) async -> Int {
        var total = 0
        let fm = FileManager.default
        if let enumerator = fm.enumerator(at: dataset.url, includingPropertiesForKeys: [.isRegularFileKey]) {
            while let url = enumerator.nextObject() as? URL {
                if Task.isCancelled { return total }
                let ext = url.pathExtension.lowercased()
                guard ["txt", "md", "json", "jsonl", "csv", "tsv", "pdf", "epub"].contains(ext) else { continue }
#if canImport(PDFKit)
                if ext == "pdf" {
                    if let doc = PDFKit.PDFDocument(url: url) {
                        var combined = ""
                        for i in 0..<doc.pageCount {
                            if let page = doc.page(at: i), let text = page.string {
                                combined += text + "\n"
                            }
                        }
                        total += await EmbeddingModel.shared.countTokens(combined)
                    }
                } else if ext == "epub" {
                    let text = EPUBTextExtractor.extractText(from: url)
                    total += await EmbeddingModel.shared.countTokens(text)
                } else if let str = try? String(contentsOf: url) {
                    total += await EmbeddingModel.shared.countTokens(str)
                }
#else
                if ext == "epub" {
                    let text = EPUBTextExtractor.extractText(from: url)
                    total += await EmbeddingModel.shared.countTokens(text)
                } else if let str = try? String(contentsOf: url) {
                    total += await EmbeddingModel.shared.countTokens(str)
                }
#endif
            }
        }
        return total
    }

    /// Reads and concatenates all eligible files within the dataset without
    /// performing any embedding or tokenization.
    func fetchAllContent(for dataset: LocalDataset) -> String {
        var parts: [String] = []
        let fm = FileManager.default
        if let enumerator = fm.enumerator(at: dataset.url, includingPropertiesForKeys: [.isRegularFileKey]) {
            while let url = enumerator.nextObject() as? URL {
                if Task.isCancelled { break }
                let ext = url.pathExtension.lowercased()
                guard ["txt", "md", "json", "jsonl", "csv", "tsv", "pdf", "epub"].contains(ext) else { continue }
#if canImport(PDFKit)
                if ext == "pdf" {
                    if let doc = PDFKit.PDFDocument(url: url) {
                        var combined = ""
                        for i in 0..<doc.pageCount {
                            if let page = doc.page(at: i), let text = page.string {
                                combined += text + "\n"
                            }
                        }
                        parts.append(combined)
                    }
                } else if ext == "epub" {
                    let text = EPUBTextExtractor.extractText(from: url)
                    parts.append(text)
                } else if let str = try? String(contentsOf: url) {
                    parts.append(str)
                }
#else
                if ext == "epub" {
                    let text = EPUBTextExtractor.extractText(from: url)
                    parts.append(text)
                } else if let str = try? String(contentsOf: url) { parts.append(str) }
#endif
            }
        }
        return parts.joined(separator: "\n\n")
    }

    /// Fetches the most relevant chunks for the provided query text from the
    /// active dataset and returns them joined with blank lines. Chunks are only
    /// returned if their similarity meets the provided threshold.
    /// Returns a concatenated context for prompting
    /// Use `fetchContextDetailed` to display per-chunk citations in UI.
    func fetchContext(
        for query: String,
        dataset: LocalDataset,
        maxChunks: Int = 3,
        minScore: Float = 0.2,
        progress: (@MainActor @Sendable (DatasetProcessingStatus) -> Void)? = nil
    ) async -> String {
        Task { await logger.log("[RAG] retrieve.begin queryLen=\(query.count) dataset=\(dataset.datasetID)") }
        
        // Validate inputs
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            Task { await logger.log("[RAG] Empty query provided") }
            return ""
        }
        
        if Task.isCancelled { return "" }
        let chunks = (try? await chunks(for: dataset, progress: progress)) ?? []
        if Task.isCancelled || chunks.isEmpty {
            Task { await logger.log("[RAG] No chunks available for dataset: \(dataset.datasetID)") }
            return "" 
        }
        
        let embedReady = await EmbeddingModel.shared.isReady()
        var selectedTexts: [String] = []
        
        if embedReady {
            let qVec = await EmbeddingModel.shared.embedQuery(trimmedQuery)
            if Task.isCancelled { return "" }
            
            // Validate embedding result
            guard !qVec.isEmpty && qVec.allSatisfy({ $0.isFinite && !$0.isNaN }) else {
                Task { await logger.log("[RAG] ❌ Invalid query embedding, falling back to lexical search") }
                selectedTexts = await performLexicalSearch(query: trimmedQuery, chunks: chunks, maxChunks: maxChunks)
                // Ensure we always have at least one fallback chunk so the prompt gets augmented
                if selectedTexts.isEmpty, let firstChunk = chunks.first?.text {
                    selectedTexts = [firstChunk]
                }
                return selectedTexts.joined(separator: "\n\n")
            }
            
            // Calculate similarities
            var scored: [(Float, String)] = []
            for c in chunks {
                if Task.isCancelled { return "" }
                
                // Validate chunk vector before computing similarity
                guard !c.vector.isEmpty && c.vector.allSatisfy({ $0.isFinite && !$0.isNaN }) else {
                    Task { await logger.log("[RAG] ⚠️ Skipping chunk with invalid vector") }
                    continue
                }
                
                let similarity = cosineSimilarity(c.vector, qVec)
                if similarity.isFinite && !similarity.isNaN {
                    scored.append((similarity, c.text))
                }
            }
            
            // Select top chunks
            var top = Array(
                scored
                    .sorted { $0.0 > $1.0 }
                    .prefix(maxChunks)
                    .filter { $0.0 >= minScore }
            )
            
            // If no chunks meet the threshold, take the best one
            if top.isEmpty, let best = scored.max(by: { $0.0 < $1.0 }) { 
                Task { await logger.log("[RAG] No chunks above threshold \(minScore), using best match: \(best.0)") }
                top = [best] 
            }
            
            selectedTexts = top.map { $0.1 }
        } else {
            // Lexical fallback when embedder is unavailable: score by token overlap
            let tokens = Set(query.lowercased()
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { $0.count >= 3 })
            func lexicalScore(_ text: String) -> Float {
                if tokens.isEmpty { return 0 }
                let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }
                if words.isEmpty { return 0 }
                var hits = 0
                var set: Set<String> = []
                for w in words {
                    let s = String(w)
                    set.insert(s)
                    if tokens.contains(s) { hits += 1 }
                }
                // Jaccard-like with small length preference for richer passages
                let j = Float(hits) / Float(max(set.count + tokens.count - hits, 1))
                let lenBonus = min(Float(text.count) / 500.0, 1.0)
                return j * 0.9 + lenBonus * 0.1
            }
            var scored: [(Float, String)] = []
            for c in chunks { scored.append((lexicalScore(c.text), c.text)) }
            // Prefer non-trivial paragraphs
            let minLen = 50
            let filtered = scored
                .filter { $0.0 > 0 }
                .sorted { $0.0 > $1.0 }
            var picked: [String] = []
            for (_, t) in filtered {
                if picked.count >= maxChunks { break }
                if t.count >= minLen { picked.append(t) }
            }
            if picked.isEmpty, let first = filtered.first?.1 { picked = [first] }
            selectedTexts = picked
        }
        guard !selectedTexts.isEmpty else { Task { await logger.log("[RAG] retrieve.none") }; return "" }
        // Token-aware clamping for safety: cap total retrieved tokens; avoid per-chunk character truncation.
        // Allocate a generous token budget here; upstream prompt builder will enforce final budget.
        let maxTotalTokens = 12000
        var out: [String] = []
        var assembled = ""
        for text in selectedTexts {
            let candidate = assembled.isEmpty ? text : assembled + "\n\n" + text
            let tok = await EmbeddingModel.shared.countTokens(candidate)
            if tok > maxTotalTokens { break }
            out.append(text)
            assembled = candidate
        }
        let result = out.joined(separator: "\n\n")
        let resultTokens = await EmbeddingModel.shared.countTokens(result)
        Task { await logger.log("[RAG] retrieve.done picked=\(out.count) totalTokens=\(resultTokens) chars=\(result.count)") }
        return result
    }

    /// Detailed retrieval suitable for citation UI
    func fetchContextDetailed(
        for query: String,
        dataset: LocalDataset,
        maxChunks: Int = 3,
        minScore: Float = 0.2,
        progress: (@MainActor @Sendable (DatasetProcessingStatus) -> Void)? = nil
    ) async -> [(text: String, source: String?)] {
        Task { await logger.log("[RAG] retrieveDetailed.begin queryLen=\(query.count) dataset=\(dataset.datasetID)") }
        if Task.isCancelled { return [] }
        let chunks = (try? await chunks(for: dataset, progress: progress)) ?? []
        if Task.isCancelled || chunks.isEmpty { return [] }
        let embedReady = await EmbeddingModel.shared.isReady()
        var candidates: [(Float, Chunk)] = []
        if embedReady {
            let qVec = await EmbeddingModel.shared.embedQuery(query)
            if qVec.isEmpty || !qVec.allSatisfy({ $0.isFinite && !$0.isNaN }) {
                Task { await logger.log("[RAG] ❌ Invalid query embedding in fetchContextDetailed, using lexical fallback") }
                // Populate candidates via lexical scoring and fall through to common handling.
                let tokens = Set(query.lowercased()
                    .split { !$0.isLetter && !$0.isNumber }
                    .map(String.init)
                    .filter { $0.count >= 3 })
                func lexicalScore(_ text: String) -> Float {
                    if tokens.isEmpty { return 0 }
                    let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }
                    if words.isEmpty { return 0 }
                    var hits = 0
                    var set: Set<String> = []
                    for w in words { let s = String(w); set.insert(s); if tokens.contains(s) { hits += 1 } }
                    let j = Float(hits) / Float(max(set.count + tokens.count - hits, 1))
                    let lenBonus = min(Float(text.count) / 500.0, 1.0)
                    return j * 0.9 + lenBonus * 0.1
                }
                candidates = chunks.map { (lexicalScore($0.text), $0) }
                    .filter { $0.0 > 0 }
                    .sorted { $0.0 > $1.0 }
                // Do not return early; common handling ensures at least one chunk is returned.
            } else {
                for c in chunks { candidates.append((cosineSimilarity(c.vector, qVec), c)) }
                candidates = candidates.sorted { $0.0 > $1.0 }.filter { $0.0 >= minScore }
            }
        } else {
            let tokens = Set(query.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 3 })
            func lexicalScore(_ text: String) -> Float {
                if tokens.isEmpty { return 0 }
                let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }
                if words.isEmpty { return 0 }
                var hits = 0
                var set: Set<String> = []
                for w in words { let s = String(w); set.insert(s); if tokens.contains(s) { hits += 1 } }
                let j = Float(hits) / Float(max(set.count + tokens.count - hits, 1))
                let lenBonus = min(Float(text.count) / 500.0, 1.0)
                return j * 0.9 + lenBonus * 0.1
            }
            candidates = chunks.map { (lexicalScore($0.text), $0) }.filter { $0.0 > 0 }.sorted { $0.0 > $1.0 }
        }
        if candidates.isEmpty, let any = chunks.first { candidates = [(0, any)] }
        // Do not character-trim individual chunks; keep full text and let token-aware injector handle final limits.
        var results: [(String, String?)] = []
        for (_, c) in candidates.prefix(maxChunks) { results.append((c.text, c.source)) }
        Task { await logger.log("[RAG] retrieveDetailed.done picked=\(results.count)") }
        return results
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        let length = min(a.count, b.count)
        if length == 0 { return 0 }
        
        // Validate input vectors
        guard a.allSatisfy({ $0.isFinite }) && b.allSatisfy({ $0.isFinite }) else {
            return 0 // Return 0 similarity for invalid vectors
        }
        
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in 0..<length {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        
        // Ensure we don't divide by zero and result is valid
        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }
        
        let similarity = dot / denominator
        return similarity.isFinite ? similarity : 0
    }
    
    private func performLexicalSearch(query: String, chunks: [Chunk], maxChunks: Int) -> [String] {
        let tokens = Set(query.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 3 })
        
        guard !tokens.isEmpty else { return [] }
        
        var scored: [(Float, String)] = []
        for chunk in chunks {
            let chunkTokens = Set(chunk.text.lowercased()
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { $0.count >= 3 })
            
            guard !chunkTokens.isEmpty else { continue }
            
            let intersection = tokens.intersection(chunkTokens).count
            if intersection > 0 {
                // Jaccard similarity with length bonus
                let union = tokens.union(chunkTokens).count
                let jaccard = Float(intersection) / Float(max(union, 1))
                let lengthBonus = min(Float(chunk.text.count) / 500.0, 1.0) * 0.1
                let score = jaccard + lengthBonus
                scored.append((score, chunk.text))
            }
        }
        
        return Array(scored
            .sorted { $0.0 > $1.0 }
            .prefix(maxChunks)
            .map { $0.1 })
    }
}
