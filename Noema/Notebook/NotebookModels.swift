import Foundation
import SwiftUI

enum CellKind: String, Codable, CaseIterable, Identifiable {
    case text
    case code
    case output

    var id: String { rawValue }
}

struct Cell: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: CellKind
    var text: String?
    var payload: Data?
    var metadata: CellMetadata?

    init(id: UUID = UUID(), kind: CellKind, text: String? = nil, payload: Data? = nil, metadata: CellMetadata? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.payload = payload
        self.metadata = metadata
    }
}

struct ConsolePersistedLine: Codable, Equatable {
    var kind: PythonLogKind
    var text: String
    var timestamp: Date
}

struct CellMetadata: Codable, Equatable {
    var lastConsole: [ConsolePersistedLine]

    init(lastConsole: [ConsolePersistedLine] = []) {
        self.lastConsole = lastConsole
    }
}

struct Notebook: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var cells: [Cell]

    init(id: UUID = UUID(), title: String = "Notebook", cells: [Cell] = []) {
        self.id = id
        self.title = title
        self.cells = cells
    }
}

@MainActor
final class NotebookStore: ObservableObject {
    @Published var notebook: Notebook
    @Published var isPythonEnabled: Bool = true {
        didSet { defaults.set(isPythonEnabled, forKey: "pythonEnabled") }
    }
    private var observer: NSObjectProtocol?
    private let defaults = UserDefaults.standard

    init(notebook: Notebook = Notebook()) {
        self.notebook = notebook
        if let stored = defaults.object(forKey: "pythonEnabled") as? Bool {
            isPythonEnabled = stored
        }
        observer = NotificationCenter.default.addObserver(forName: .pythonSettingsDidChange, object: nil, queue: .main) { [weak self] note in
            guard let value = note.object as? Bool else { return }
            self?.isPythonEnabled = value
        }
    }

    func addCell(kind: CellKind, after cell: Cell? = nil) {
        let newCell = Cell(kind: kind, text: kind == .output ? nil : "")
        if let cell, let index = notebook.cells.firstIndex(of: cell) {
            notebook.cells.insert(newCell, at: index + 1)
        } else {
            notebook.cells.append(newCell)
        }
    }

    func removeCell(_ cell: Cell) {
        notebook.cells.removeAll { $0.id == cell.id }
    }

    func update(cell: Cell, text: String) {
        guard let idx = notebook.cells.firstIndex(of: cell) else { return }
        notebook.cells[idx].text = text
    }

    func appendOutput(stdout: String, stderr: String, tables: [Data], images: [Data]) {
        var summary: [String] = []
        if !stdout.isEmpty { summary.append("```text\n\(stdout)\n```") }
        if !stderr.isEmpty { summary.append("```error\n\(stderr)\n```") }
        if !tables.isEmpty { summary.append("Tables: \(tables.count)") }
        if !images.isEmpty { summary.append("Images: \(images.count)") }
        let text = summary.joined(separator: "\n\n")
        let cell = Cell(kind: .output, text: text)
        notebook.cells.append(cell)
    }

    func apply(pythonResult: PythonExecuteResult) {
        var summaryParts: [String] = []
        if !pythonResult.stdout.isEmpty {
            summaryParts.append("```text\n\(pythonResult.stdout)\n```")
        }
        if !pythonResult.stderr.isEmpty {
            summaryParts.append("```error\n\(pythonResult.stderr)\n```")
        }
        if !summaryParts.isEmpty {
            notebook.cells.append(Cell(kind: .output, text: summaryParts.joined(separator: "\n\n")))
        }
        for (idx, tableString) in pythonResult.tables.enumerated() {
            if let data = Data(base64Encoded: tableString) {
                var cell = Cell(kind: .output, payload: data)
                cell.text = "Table \(idx + 1)"
                notebook.cells.append(cell)
            }
        }
        for (idx, imageString) in pythonResult.images.enumerated() {
            if let data = Data(base64Encoded: imageString) {
                var cell = Cell(kind: .output, payload: data)
                cell.text = "Image \(idx + 1)"
                notebook.cells.append(cell)
            }
        }
    }

    func exportMarkdown() -> String {
        var components: [String] = ["# \(notebook.title)"]
        for cell in notebook.cells {
            switch cell.kind {
            case .text:
                components.append(cell.text ?? "")
            case .code:
                components.append("```python\n\(cell.text ?? "")\n```")
            case .output:
                components.append(cell.text ?? "")
            }
        }
        return components.joined(separator: "\n\n")
    }

    func exportMetadata() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(notebook)
    }

    func importNotebook(markdown: String, metadata: Data) throws {
        let decoder = JSONDecoder()
        let imported = try decoder.decode(Notebook.self, from: metadata)
        notebook = imported
    }

    func updateConsoleHistory(for cell: Cell, history: [ConsolePersistedLine], maxHistory: Int) {
        guard let idx = notebook.cells.firstIndex(of: cell) else { return }
        var trimmed = history
        if trimmed.count > maxHistory {
            trimmed = Array(trimmed.suffix(maxHistory))
        }
        var meta = notebook.cells[idx].metadata ?? CellMetadata()
        meta.lastConsole = trimmed
        notebook.cells[idx].metadata = meta
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}
