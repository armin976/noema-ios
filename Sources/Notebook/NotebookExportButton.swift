#if canImport(SwiftUI)
import SwiftUI
import NoemaCore

public struct NotebookExportButton<Label: View>: View {
    private let exporter: ReproExporter
    private let documentsDirectory: URL
    private let onExported: (URL) -> Void
    private let label: () -> Label

    @State private var isExporting = false
    @State private var lastError: String?

    public init(exporter: ReproExporter,
                documentsDirectory: URL,
                onExported: @escaping (URL) -> Void,
                @ViewBuilder label: @escaping () -> Label) {
        self.exporter = exporter
        self.documentsDirectory = documentsDirectory
        self.onExported = onExported
        self.label = label
    }

    public var body: some View {
        Button(action: export) {
            ZStack {
                label()
                if isExporting {
                    ProgressView().progressViewStyle(.circular)
                }
            }
        }
        .disabled(isExporting)
        .alert("Export Failed", isPresented: Binding(get: { lastError != nil }, set: { _ in lastError = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(lastError ?? "Unknown error")
        }
    }

    private func export() {
        guard !isExporting else { return }
        isExporting = true
        Task {
            do {
                let url = try await exporter.exportCurrentNotebook(to: documentsDirectory)
                onExported(url)
            } catch {
                lastError = error.localizedDescription
            }
            isExporting = false
        }
    }
}
#endif
