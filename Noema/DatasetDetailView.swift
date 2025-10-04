// DatasetDetailView.swift
import SwiftUI

struct DatasetDetailView: View, Identifiable {
    let id = UUID()
    let detail: DatasetDetails
    @EnvironmentObject var downloadController: DownloadController
    @Environment(\.dismiss) private var dismiss
    @StateObject private var readmeLoader: DatasetReadmeLoader
    @AppStorage("huggingFaceToken") private var huggingFaceToken = ""
    @State private var showRecommendation = false

    private var isOTL: Bool { detail.id.hasPrefix("OTL/") }
    private var activeItem: DownloadController.DatasetItem? {
        downloadController.datasetItems.first { $0.detail.id == detail.id }
    }
    
    private var totalPDFSize: Int64 {
        detail.files
            .filter { $0.downloadURL.pathExtension.lowercased() == "pdf" }
            .reduce(0) { $0 + $1.sizeBytes }
    }

    init(detail: DatasetDetails) {
        self.detail = detail
        let token = UserDefaults.standard.string(forKey: "huggingFaceToken") ?? ""
        _readmeLoader = StateObject(wrappedValue: DatasetReadmeLoader(repo: detail.id, token: token))
    }

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text(detail.displayName ?? detail.id)) {
                    if isOTL {
                        if let summary = detail.summary { Text(summary) }
                    } else {
                        ReadmeCollapseView(markdown: readmeLoader.markdown,
                                          loading: readmeLoader.isLoading,
                                          retry: { readmeLoader.load(force: true) })
                            .onAppear { readmeLoader.load() }
                            .onDisappear {
                                readmeLoader.clearMarkdown()
                                readmeLoader.cancel()
                            }
                    }
                }
                Section("Files") {
                    let supported: Set<String> = ["pdf", "epub", "txt", "md", "json", "jsonl", "csv", "tsv"]
                    let hasUsable = detail.files.contains { f in
                        let ext = f.downloadURL.pathExtension.lowercased()
                        return supported.contains(ext)
                    }
                    let unsupportedExts: [String] = detail.files
                        .map { $0.downloadURL.pathExtension.lowercased() }
                        .filter { !$0.isEmpty && !supported.contains($0) }
                    let hasOnlyUnsupported = !detail.files.isEmpty && !hasUsable

                    if detail.files.isEmpty {
                        Text("No files listed for this dataset.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(detail.files) { f in
                            HStack {
                                Text(f.name)
                                Spacer()
                                Text(ByteCountFormatter.string(fromByteCount: f.sizeBytes, countStyle: .file))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if hasOnlyUnsupported {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("This dataset's files are not currently supported for document retrieval.")
                                Text("Supported formats: PDF, EPUB, TXT, MD, JSON, JSONL, CSV, TSV")
                                Text("Try another dataset if these formats aren't available.")
                                if !unsupportedExts.isEmpty {
                                    let list = Array(Set(unsupportedExts)).prefix(5).joined(separator: ", ")
                                    Text("Found unsupported: \(list) …")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        } else if isOTL && !hasUsable {
                            Text("This textbook appears to be available only as a web page. Noema can't import it as a dataset.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    let supported: Set<String> = ["pdf", "epub", "txt", "md", "json", "jsonl", "csv", "tsv"]
                    let hasUsable = detail.files.contains { f in
                        let ext = f.downloadURL.pathExtension.lowercased()
                        return supported.contains(ext)
                    }
                    if let item = activeItem {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                if item.expectedBytes > 0 {
                                    ProgressView(value: Double(item.downloadedBytes), total: Double(item.expectedBytes))
                                        .frame(maxWidth: .infinity)
                                } else {
                                    ProgressView(value: item.progress)
                                        .frame(maxWidth: .infinity)
                                }
                                let pct = item.expectedBytes > 0
                                    ? Int(Double(item.downloadedBytes) / Double(item.expectedBytes) * 100)
                                    : Int(item.progress * 100)
                                let speedStr: String = {
                                    if item.speed > 0 {
                                        return ByteCountFormatter.string(fromByteCount: Int64(item.speed), countStyle: .file) + "/s"
                                    } else { return "" }
                                }()
                                Text(speedStr.isEmpty ? "\(pct)%" : "\(pct)%  ·  \(speedStr)")
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            Text(item.completed ? "Download complete" : "Downloading…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if item.completed {
                                Button("Done") { dismiss() }
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                    } else {
                        // Show recommendation button for OTL datasets with PDFs
                        if isOTL && totalPDFSize > 0 {
                            Button {
                                showRecommendation = true
                            } label: {
                                Label("Check Requirements", systemImage: "info.circle.fill")
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 8)
                        }
                        
                        Button("Download Dataset") {
                            downloadController.startDataset(detail: detail)
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                        .disabled(!hasUsable)
                        .opacity(hasUsable ? 1 : 0.5)
                        if !hasUsable {
                            Text("No compatible files found for retrieval. Supported: PDF, EPUB, TXT, MD, JSON, JSONL, CSV, TSV")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if let item = activeItem {
                        Button("Done") { dismiss() }
                            .disabled(!item.completed && !isOTL)
                    } else {
                        Button("Close") { dismiss() }
                    }
                }
            }
            .sheet(isPresented: $showRecommendation) {
                DatasetRecommendationView(
                    datasetName: detail.displayName ?? detail.id,
                    totalSizeBytes: totalPDFSize
                )
            }
        }
    }
}
