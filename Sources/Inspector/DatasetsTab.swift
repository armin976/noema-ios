import SwiftUI
import UIKit

public struct InspectorPythonExecutionResult {
    public let stdout: String

    public init(stdout: String) {
        self.stdout = stdout
    }
}

public protocol InspectorPythonExecutionHandling {
    func runPython(code: String, fileIDs: [String], timeoutMs: Int, force: Bool) async throws -> InspectorPythonExecutionResult
}

struct DatasetsTab: View {
    let store: DatasetIndexStore
    let pythonExecutor: InspectorPythonExecutionHandling?
    @State private var datasets: [DatasetInfo] = []
    @State private var hashing: Set<UUID> = []
    @State private var sampling: Set<UUID> = []
    @State private var errorMessage: String?
    @State private var showingError = false

    private let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()

    private let dateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter
    }()

    init(store: DatasetIndexStore, pythonExecutor: InspectorPythonExecutionHandling? = nil) {
        self.store = store
        self.pythonExecutor = pythonExecutor
    }

    var body: some View {
        NavigationStack {
            List {
                if datasets.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("No mounted datasets", systemImage: "tray")
                                .font(.headline)
                            Text("Mount a CSV in the notebook to see it here.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 16)
                    }
                } else {
                    ForEach(datasets) { dataset in
                        datasetRow(dataset)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Datasets")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: refresh) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
            .task { await loadInitial() }
            .alert("Inspector Error", isPresented: $showingError, actions: {
                Button("OK", role: .cancel) {}
            }, message: {
                Text(errorMessage ?? "Unknown error")
            })
            .refreshable { await refreshAsync() }
        }
    }

    private func loadInitial() async {
        let items = await store.listMounted()
        await MainActor.run { datasets = items }
    }

    private func refresh() {
        Task { await refreshAsync() }
    }

    private func refreshAsync() async {
        let items = await store.listMounted()
        await MainActor.run { datasets = items }
    }

    @ViewBuilder
    private func datasetRow(_ info: DatasetInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(info.name)
                    .font(.headline)
                    .lineLimit(2)
                Spacer()
                Text(sizeFormatter.string(fromByteCount: info.size))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Label("Modified", systemImage: "clock")
                    .labelStyle(.titleOnly)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(dateFormatter.localizedString(for: info.mtime, relativeTo: Date()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    Label("SHA-256", systemImage: "number")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                    Text(info.sha256 ?? "Tap “Hash now”")
                        .font(.footnote.monospaced())
                        .foregroundStyle(info.sha256 == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack(alignment: .center, spacing: 8) {
                    Label("Shape", systemImage: "tablecells")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                    if let rows = info.rows, let cols = info.cols {
                        Text("\(rows) × \(cols)")
                            .font(.footnote)
                    } else {
                        Text("Quick sample to estimate rows × cols")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            actionRow(for: info)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func actionRow(for info: DatasetInfo) -> some View {
        HStack {
            Button {
                hash(info)
            } label: {
                if hashing.contains(info.id) {
                    ProgressView()
                        .progressViewStyle(.circular)
                } else {
                    Label("Hash now", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .buttonStyle(.bordered)
            .disabled(hashing.contains(info.id))

            Button {
                sample(info)
            } label: {
                if sampling.contains(info.id) {
                    ProgressView()
                        .progressViewStyle(.circular)
                } else {
                    Label("Quick sample", systemImage: "sparkles")
                }
            }
            .buttonStyle(.bordered)
            .disabled(sampling.contains(info.id) || pythonExecutor == nil)

            Spacer()

            Menu {
                Button("Reveal in Files", systemImage: "folder") {
                    FileRevealer.shared.reveal(info.url)
                }
                Button("Copy path", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = info.url.path
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
        .font(.subheadline)
    }

    private func hash(_ info: DatasetInfo) {
        guard !hashing.contains(info.id) else { return }
        hashing.insert(info.id)
        Task {
            do {
                let hash = try await store.computeHash(for: info.url)
                var updated = info
                updated.sha256 = hash
                updated.updatedAt = Date()
                await store.upsert(updated)
                await refreshAsync()
            } catch {
                await present(error: error)
            }
            await MainActor.run {
                hashing.remove(info.id)
            }
        }
    }

    private func sample(_ info: DatasetInfo) {
        guard !sampling.contains(info.id), let executor = pythonExecutor else { return }
        sampling.insert(info.id)
        Task {
            let sampler = DatasetShapeSampler(store: store, pythonExecutor: executor)
            if let shape = await sampler.sampleShape(for: info) {
                var updated = info
                updated.rows = shape.rows
                updated.cols = shape.cols
                updated.updatedAt = Date()
                await store.upsert(updated)
                await refreshAsync()
            }
            await MainActor.run {
                sampling.remove(info.id)
            }
        }
    }

    private func present(error: Error) async {
        await MainActor.run {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

private struct DatasetShapeSampler {
    let store: DatasetIndexStore
    private let pythonExecutor: InspectorPythonExecutionHandling

    init(store: DatasetIndexStore, pythonExecutor: InspectorPythonExecutionHandling) {
        self.store = store
        self.pythonExecutor = pythonExecutor
    }

    func sampleShape(for info: DatasetInfo) async -> (rows: Int, cols: Int)? {
        guard let relative = await store.relativePath(for: info.url) else { return nil }
        let fileLiteral = Self.pythonStringLiteral(info.url.lastPathComponent)
        let code = """
import pandas as pd
import json
from pathlib import Path
path = Path('/data') / \(fileLiteral)
try:
    df = pd.read_csv(path, nrows=200)
    print(json.dumps({"rows": int(df.shape[0]), "cols": int(df.shape[1])}))
except Exception:
    pass
"""
        do {
            let result = try await pythonExecutor.runPython(code: code,
                                                            fileIDs: [relative],
                                                            timeoutMs: 2_000,
                                                            force: true)
            return parseShape(from: result.stdout)
        } catch {
            return nil
        }
    }

    private func parseShape(from stdout: String) -> (Int, Int)? {
        let lines = stdout.split(whereSeparator: { $0.isNewline })
        for line in lines.reversed() {
            if let data = line.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let rows = object["rows"] as? Int,
               let cols = object["cols"] as? Int {
                return (rows, cols)
            }
        }
        return nil
    }

    private static func pythonStringLiteral(_ value: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: ["value": value]),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let encoded = json["value"] {
            return "\"\(encoded)\""
        }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

final class FileRevealer: NSObject, UIDocumentInteractionControllerDelegate {
    static let shared = FileRevealer()
    private var controller: UIDocumentInteractionController?

    func reveal(_ url: URL) {
        let controller = UIDocumentInteractionController(url: url)
        controller.delegate = self
        self.controller = controller
        guard let presenter = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?.rootViewController else { return }
        controller.presentOptionsMenu(from: presenter.view.bounds, in: presenter.view, animated: true)
    }

    func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
        guard let presenter = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?.rootViewController else {
            return UIViewController()
        }
        return presenter
    }
}
