// DatasetDetailView.swift
import SwiftUI

struct DatasetDetailView: View, Identifiable {
    let id = UUID()
    let detail: DatasetDetails
    @EnvironmentObject var downloadController: DownloadController
    @Environment(\.dismiss) private var dismiss
#if os(macOS)
    @Environment(\.macModalDismiss) private var macModalDismiss
#endif
    @Environment(\.locale) private var locale
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

    private var fileSizeFormatter: MeasurementFormatter {
        let f = MeasurementFormatter()
        f.locale = locale
        f.unitOptions = .naturalScale
        f.unitStyle = .medium
        f.numberFormatter.locale = locale
        f.numberFormatter.maximumFractionDigits = 1
        f.numberFormatter.minimumFractionDigits = 0
        return f
    }

    init(detail: DatasetDetails) {
        self.detail = detail
        let token = UserDefaults.standard.string(forKey: "huggingFaceToken") ?? ""
        _readmeLoader = StateObject(wrappedValue: DatasetReadmeLoader(repo: detail.id, token: token))
    }

    private func close() {
#if os(macOS)
        macModalDismiss()
#else
        dismiss()
#endif
    }

    var body: some View {
        #if os(macOS)
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Header
                VStack(alignment: .leading, spacing: 12) {
                    Text(detail.displayName ?? detail.id)
                        .font(.system(.title, design: .serif))
                        .fontWeight(.bold)
                    if let summary = detail.summary {
                        Text(summary)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                    }
                }
                .padding(.bottom, 8)

                // Readme / Description
                if !isOTL {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(LocalizedStringKey("About"))
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        ReadmeCollapseView(markdown: readmeLoader.markdown,
                                          loading: readmeLoader.isLoading,
                                          retry: { readmeLoader.load(force: true) })
                            .frame(minHeight: 100)
                            .padding()
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(12)
                    }
                    .onAppear { readmeLoader.load() }
                    .onDisappear {
                        readmeLoader.clearMarkdown()
                        readmeLoader.cancel()
                    }
                }

                // Files
                VStack(alignment: .leading, spacing: 16) {
                    Text(LocalizedStringKey("Files"))
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    filesContent
                        .padding()
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(12)
                }

                // Actions
                VStack(alignment: .leading, spacing: 16) {
                    Text(LocalizedStringKey("Actions"))
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    actionsContent
                        .padding()
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(12)
                }
            }
            .padding(32)
        }
        .sheet(isPresented: $showRecommendation) {
            DatasetRecommendationView(
                datasetName: detail.displayName ?? detail.id,
                totalSizeBytes: totalPDFSize
            )
        }
        #else
        NavigationStack {
            List {
                let supportedFormatsList = "PDF, EPUB, TXT, MD, JSON, JSONL, CSV, TSV"
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
                Section(LocalizedStringKey("Files")) {
                    filesContent
                }
                Section {
                    actionsContent
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if let item = activeItem {
                        Button(LocalizedStringKey("Done")) { close() }
                            .disabled(!item.completed && !isOTL)
                    } else {
                        Button(LocalizedStringKey("Close")) { close() }
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
        #endif
    }

    @ViewBuilder
    private var filesContent: some View {
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
            Text(LocalizedStringKey("No files listed for this dataset."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(detail.files.enumerated()), id: \.element.id) { index, f in
                    if index > 0 { Divider() }
                    HStack(spacing: 12) {
                        Image(systemName: "doc.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text(f.name)
                            .font(.body)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(fileSizeFormatter.string(from: Measurement(value: Double(f.sizeBytes), unit: UnitInformationStorage.bytes)))
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                }
            }
            
            if hasOnlyUnsupported {
                VStack(alignment: .leading, spacing: 8) {
                    Divider().padding(.vertical, 4)
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(LocalizedStringKey("This dataset's files are not currently supported for document retrieval."))
                                .font(.callout)
                                .fontWeight(.medium)
                            
                            Text(
                                String.localizedStringWithFormat(
                                    String(localized: "Supported formats: %@", locale: locale),
                                    "PDF, EPUB, TXT, MD, JSON, JSONL, CSV, TSV"
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            } else if isOTL && !hasUsable {
                Divider().padding(.vertical, 4)
                Text(LocalizedStringKey("This textbook appears to be available only as a web page. Noema can't import it as a dataset."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var actionsContent: some View {
        let supported: Set<String> = ["pdf", "epub", "txt", "md", "json", "jsonl", "csv", "tsv"]
        let hasUsable = detail.files.contains { f in
            let ext = f.downloadURL.pathExtension.lowercased()
            return supported.contains(ext)
        }
        
        if let item = activeItem {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    if item.expectedBytes > 0 {
                        ProgressView(value: Double(item.downloadedBytes), total: Double(item.expectedBytes))
                            .frame(maxWidth: .infinity)
                            .tint(.blue)
                    } else {
                        ProgressView(value: item.progress)
                            .frame(maxWidth: .infinity)
                            .tint(.blue)
                    }
                    let pct = item.expectedBytes > 0
                        ? Int(Double(item.downloadedBytes) / Double(item.expectedBytes) * 100)
                        : Int(item.progress * 100)
                    let speedStr: String = {
                        if item.speed > 0 {
                            let measurement = Measurement(value: Double(item.speed), unit: UnitInformationStorage.bytes)
                            return fileSizeFormatter.string(from: measurement) + "/s"
                        } else { return "" }
                    }()
                    Text(speedStr.isEmpty ? "\(pct)%" : "\(pct)%  ·  \(speedStr)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Text(item.completed
                     ? String(localized: "Download complete", locale: locale)
                     : String(localized: "Downloading…", locale: locale)
                )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if item.completed {
                    Button(LocalizedStringKey("Done")) { close() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            }
        } else {
            // Show recommendation button for OTL datasets with PDFs
            if isOTL && totalPDFSize > 0 {
                Button {
                    showRecommendation = true
                } label: {
                    Label(LocalizedStringKey("Check Requirements"), systemImage: "info.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .padding(.bottom, 8)
            }
            
            Button {
                downloadController.startDataset(detail: detail)
            } label: {
                Text(LocalizedStringKey("Download Dataset"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!hasUsable)
            .opacity(hasUsable ? 1 : 0.5)
            
            if !hasUsable {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                    Text(
                        String.localizedStringWithFormat(
                            String(localized: "No compatible files found. Supported: %@", locale: locale),
                            "PDF, EPUB, TXT, MD, JSON, JSONL, CSV, TSV"
                        )
                    )
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            }
        }
    }
}
