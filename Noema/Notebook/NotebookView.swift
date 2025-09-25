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
    @State private var showingInspectorSheet = false
    @State private var navigatingToInspector = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private let pythonExecutor = PythonExecuteTool()

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
                Button {
                    if let code = cell.text {
                        onRunCode?(code)
                    }
                } label: {
                    Label("Run", systemImage: "play.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.isPythonEnabled)
                if !store.isPythonEnabled {
                    Text("Enable offline Python in Settings to run code.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
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
