import SwiftUI
import UIKit
import Inspector

struct NotebookView: View {
    @ObservedObject var store: NotebookStore
    var onRunCode: ((String) -> Void)?
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var exportedMarkdown: String = ""
    @State private var exportedMetadata: Data = Data()
    @State private var consoleLines: [UUID: [ConsoleLine]] = [:]
    @State private var consoleTasks: [UUID: Task<Void, Never>] = [:]
    @State private var consoleOpen: Set<UUID> = []
    @State private var showingInspectorSheet = false
    @State private var navigatingToInspector = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private let pythonExecutor = PythonExecuteTool()
main

    var body: some View {
        VStack(alignment: .leading) {
            NavigationLink(destination: InspectorView(pythonExecutor: pythonExecutor).navigationTitle("Inspector"), isActive: $navigatingToInspector) {
                EmptyView()
            }
            .hidden()
            header
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(store.notebook.cells) { cell in
                        cellView(cell)
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { exportedMarkdown = store.exportMarkdown(); exportedMetadata = (try? store.exportMetadata()) ?? Data(); showingExporter = true } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                Button { showingImporter = true } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                Menu {
                    Button("Inspector", systemImage: "magnifyingglass") {
                        openInspector()
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingExporter) {
            NavigationStack {
                VStack(alignment: .leading) {
                    Text("Markdown")
                        .font(.headline)
                    ScrollView { Text(exportedMarkdown).font(.footnote).frame(maxWidth: .infinity, alignment: .leading) }
                        .padding()
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Text("Metadata JSON")
                        .font(.headline)
                        .padding(.top)
                    ScrollView { Text(String(data: exportedMetadata, encoding: .utf8) ?? "{}")
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                        .padding()
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Spacer()
                }
                .padding()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showingExporter = false } } }
                .navigationTitle("Export Notebook")
            }
        }
        .sheet(isPresented: $showingImporter) {
            NavigationStack {
                ImportNotebookView { markdown, metadata in
                    do {
                        try store.importNotebook(markdown: markdown, metadata: metadata)
                        showingImporter = false
                    } catch {
                        // noop placeholder
                    }
                }
            }
        }
        .sheet(isPresented: $showingInspectorSheet) {
            NavigationStack {
                InspectorView(pythonExecutor: pythonExecutor)
                    .navigationTitle("Inspector")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showingInspectorSheet = false } } }
            }
        }
    }

    private var header: some View {
        HStack {
            TextField("Notebook Title", text: Binding(
                get: { store.notebook.title },
                set: { store.notebook.title = $0 }
            ))
            .font(.title2.weight(.semibold))
            .textFieldStyle(.roundedBorder)
            Spacer()
            Menu {
                Button("Add Text") { store.addCell(kind: .text) }
                Button("Add Code") { store.addCell(kind: .code) }
                Button("Add Output") { store.addCell(kind: .output) }
            } label: {
                Label("Add", systemImage: "plus")
            }
        }
        .padding([.horizontal, .top])
    }

    @ViewBuilder
    private func cellView(_ cell: Cell) -> some View {
        switch cell.kind {
        case .text:
            TextEditor(text: Binding(
                get: { cell.text ?? "" },
                set: { store.update(cell: cell, text: $0) }
            ))
            .frame(minHeight: 80)
        case .code:
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: Binding(
                    get: { cell.text ?? "" },
                    set: { store.update(cell: cell, text: $0) }
                ))
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 120)
                HStack(spacing: 12) {
                    Button {
                        runCell(cell)
                    } label: {
                        Label("Run", systemImage: "play.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!store.isPythonEnabled)

                    Button {
                        toggleConsole(for: cell)
                    } label: {
                        Label("Console", systemImage: "terminal")
                    }
                    .buttonStyle(.bordered)
                }
                if !store.isPythonEnabled {
                    Text("Enable offline Python in Settings to run code.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if consoleOpen.contains(cell.id) {
                    ConsoleView(lines: consoleLines[cell.id] ?? [])
                        .frame(minHeight: 120)
                }
            }
            .onAppear { ensureConsoleState(for: cell) }
        case .output:
            OutputCellView(cell: cell)
        }
    }
}

private extension NotebookView {
    func openInspector() {
        if horizontalSizeClass == .regular {
            showingInspectorSheet = true
        } else {
            navigatingToInspector = true
        }
    }
}

private struct ImportNotebookView: View {
    var onImport: (String, Data) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var markdown: String = ""
    @State private var metadata: String = ""

    var body: some View {
        Form {
            Section("Markdown") {
                TextEditor(text: $markdown)
                    .frame(height: 120)
                    .font(.footnote)
            }
            Section("Metadata JSON") {
                TextEditor(text: $metadata)
                    .frame(height: 120)
                    .font(.footnote)
            }
            Button("Import") {
                let data = metadata.data(using: .utf8) ?? Data()
                onImport(markdown, data)
                dismiss()
            }
        }
        .navigationTitle("Import Notebook")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }
}

private struct OutputCellView: View {
    let cell: Cell

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let text = cell.text, !text.isEmpty {
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let payload = cell.payload {
                if let table = try? decodeTable(from: payload) {
                    TableView(table: table)
                } else if let image = UIImage(data: payload) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func decodeTable(from data: Data) throws -> [[String: String]] {
        let obj = try JSONSerialization.jsonObject(with: data)
        guard let dict = obj as? [String: Any],
              let dataArray = dict["data"] as? [[String: Any]] else {
            return []
        }
        return dataArray.map { row in
            row.reduce(into: [:]) { partialResult, pair in
                partialResult[pair.key] = String(describing: pair.value)
            }
        }
    }
}

private struct TableView: View {
    let table: [[String: String]]

    var body: some View {
        if let first = table.first {
            let keys = Array(first.keys)
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        ForEach(keys, id: \.self) { key in
                            Text(key)
                                .font(.headline)
                                .padding(6)
                                .frame(minWidth: 80, alignment: .leading)
                                .background(Color(.systemGray5))
                        }
                    }
                    ForEach(table.indices, id: \.self) { index in
                        let row = table[index]
                        HStack {
                            ForEach(keys, id: \.self) { key in
                                Text(row[key] ?? "")
                                    .font(.footnote)
                                    .frame(minWidth: 80, alignment: .leading)
                                    .padding(6)
                            }
                        }
                        .background(index.isMultiple(of: 2) ? Color(.systemGray6) : Color.clear)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("No data")
        }
    }
}

extension NotebookView {
    private func toggleConsole(for cell: Cell) {
        ensureConsoleState(for: cell)
        if consoleOpen.contains(cell.id) {
            consoleOpen.remove(cell.id)
        } else {
            consoleOpen.insert(cell.id)
        }
    }

    private func ensureConsoleState(for cell: Cell) {
        if consoleLines[cell.id] == nil {
            let persisted = cell.metadata?.lastConsole.map { ConsoleLine(persisted: $0) } ?? []
            consoleLines[cell.id] = persisted
        }
    }

    private func appendConsoleLine(_ text: String, kind: PythonLogKind, timestamp: Date, cellID: UUID) {
        var lines = consoleLines[cellID] ?? []
        if kind == .status, let last = lines.last, last.kind == .status, last.text == text {
            return
        }
        lines.append(ConsoleLine(kind: kind, text: text, timestamp: timestamp))
        if lines.count > 600 {
            lines.removeFirst(lines.count - 600)
        }
        consoleLines[cellID] = lines
    }

    private func persistConsoleHistory(for cell: Cell, maxHistory: Int) {
        guard let current = store.notebook.cells.first(where: { $0.id == cell.id }) else { return }
        let lines = consoleLines[cell.id] ?? []
        let trimmed = lines.count > maxHistory ? Array(lines.suffix(maxHistory)) : lines
        consoleLines[cell.id] = trimmed
        store.updateConsoleHistory(for: current, history: trimmed.map { $0.toPersisted() }, maxHistory: maxHistory)
    }

    private func runCell(_ cell: Cell) {
        guard store.isPythonEnabled else { return }
        guard let code = cell.text?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty else { return }
        let defaults = UserDefaults.standard
        let autoOpen = defaults.object(forKey: "console.autoOpenOnRun") as? Bool ?? true
        let maxHistory = defaults.object(forKey: "console.maxHistoryLines") as? Int ?? 300
        if autoOpen {
            consoleOpen.insert(cell.id)
        }
        consoleTasks[cell.id]?.cancel()
        consoleLines[cell.id] = []
        consoleTasks[cell.id] = Task { @MainActor in
            defer {
                persistConsoleHistory(for: cell, maxHistory: maxHistory)
                consoleTasks[cell.id] = nil
            }

            appendConsoleLine("starting", kind: .status, timestamp: Date(), cellID: cell.id)
            let mountFiles: [PythonMountFile] = []
            let key = PyRunKey(code: code, files: mountFiles, runnerVersion: PythonExecuteTool.toolVersion)

            do {
                if let entry = PythonResultCache.shared.lookup(key) {
                    appendConsoleLine("caching", kind: .status, timestamp: Date(), cellID: cell.id)
                    appendConsoleLine("finished", kind: .status, timestamp: Date(), cellID: cell.id)
                    let result = try entry.loadResult()
                    NotificationCenter.default.post(name: .pythonExecutionDidComplete, object: result.toExecuteResult())
                    return
                }

                let (runID, stream) = try await PythonRuntimeManager.shared.runWithStreaming(code: code, files: mountFiles, timeout: 15_000)
                do {
                    for await event in stream {
                        guard !Task.isCancelled else { break }
                        appendConsoleLine(event.line, kind: event.kind, timestamp: event.ts, cellID: cell.id)
                    }
                }
                let result = try await PythonRuntimeManager.shared.awaitResult(for: runID)
                try PythonResultCache.shared.write(key, from: result)
                NotificationCenter.default.post(name: .pythonExecutionDidComplete, object: result.toExecuteResult())
            } catch {
                if Task.isCancelled { return }
                appendConsoleLine(error.localizedDescription, kind: .stderr, timestamp: Date(), cellID: cell.id)
            }
        }
    }
}
