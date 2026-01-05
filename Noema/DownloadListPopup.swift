// DownloadListPopup.swift
import SwiftUI

struct DownloadListPopup: View {
    @EnvironmentObject var controller: DownloadController
    @Environment(\.dismiss) private var dismiss

    var onClose: (() -> Void)? = nil

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(controller.items) { item in
                    row(for: item)
                }
                ForEach(controller.leapItems) { item in
                    leapRow(for: item)
                }
                ForEach(controller.datasetItems) { item in
                    datasetRow(for: item)
                }
                ForEach(controller.embeddingItems) { item in
                    embeddingRow(for: item)
                }
            }
            .navigationTitle("Downloads")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { close() } } }
        }
    }

    // MARK: – Row view
    @ViewBuilder
    private func row(for item: DownloadController.Item) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(prettyName(item.detail.id))
                Text(item.quant.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                ProgressView(value: item.progress)
                HStack(spacing: 8) {
                    // Error state or progress
                    if let error = item.error {
                        if error.isRetryable {
                            Text(error.localizedDescription)
                                .font(.caption2)
                                .foregroundStyle(.red)
                        } else {
                            Text("Failed: \(error.localizedDescription)")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    } else {
                        Text("\(Int(item.progress * 100)) %")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(speedText(item.speed))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if item.mmprojSize > 0 {
                            Text("(+ mmproj \(Int(item.mmprojProgress * 100))%)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Control buttons
                    if let error = item.error, error.isRetryable {
                        // Show retry button for network errors
                        Button { controller.resume(itemID: item.id) } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("Retry download")
                    } else if controller.paused.contains(item.id) {
                        // Show resume button for intentionally paused downloads
                        Button { controller.resume(itemID: item.id) } label: {
                            Image(systemName: "play.fill")
                        }
                        .buttonStyle(.borderless)
                    } else if item.error == nil {
                        // Show pause button for active downloads
                        Button { controller.pause(itemID: item.id) } label: {
                            Image(systemName: "pause.fill")
                        }
                        .buttonStyle(.borderless)
                    }
                    
                    // Always show cancel/stop button
                    Button { controller.cancel(itemID: item.id) } label: {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    @ViewBuilder
    private func leapRow(for item: DownloadController.LeapItem) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(item.entry.displayName)
                Text(item.entry.slug)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                ProgressView(value: item.progress)
                    .modernProgress()
                HStack {
                    Text("\(Int(item.progress * 100)) %")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(speedText(item.speed))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button { controller.cancel(itemID: item.id) } label: {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    @ViewBuilder
    private func datasetRow(for item: DownloadController.DatasetItem) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(prettyName(item.detail.id))
                Text(item.detail.id)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                if item.expectedBytes > 0 {
                    ProgressView(value: Double(item.downloadedBytes), total: Double(item.expectedBytes))
                } else {
                    ProgressView(value: item.progress)
                }
                HStack {
                    let pct = item.expectedBytes > 0
                        ? Int(Double(item.downloadedBytes) / Double(item.expectedBytes) * 100)
                        : Int(item.progress * 100)
                    Text("\(pct) %")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(speedText(item.speed))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button { controller.cancel(itemID: item.id) } label: {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    @ViewBuilder
    private func embeddingRow(for item: DownloadController.EmbeddingItem) -> some View {
        HStack {
            Text(prettyName(item.repoID))
            Spacer()
            VStack(alignment: .trailing) {
                ProgressView(value: item.progress)
                HStack {
                    Text("\(Int(item.progress * 100)) %")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button { controller.cancel(itemID: item.id) } label: {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private func speedText(_ speed: Double) -> String {
        guard speed > 0 else { return "--" }
        let kb = speed / 1024
        if kb > 1024 { return String(format: "%.1f MB/s", kb / 1024) }
        return String(format: "%.0f KB/s", kb)
    }

    private func prettyName(_ id: String) -> String {
        let base = id.split(separator: "/").last.map(String.init) ?? id
        var cleaned = base.replacingOccurrences(of: "[-_]", with: " ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "(?i)gguf", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "(?i)ggml", with: "", options: .regularExpression)
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.split(separator: " ").map { $0.capitalized }.joined(separator: " ")
    }
}
