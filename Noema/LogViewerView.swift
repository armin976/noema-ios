// LogViewerView.swift
import SwiftUI

struct LogViewerView: View {
    let url: URL

    @State private var text = ""
    @Environment(\.dismiss) private var dismiss
    @State private var timer: Timer?

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .monospaced()
                .onAppear { load(); startTimer() }
                .onDisappear { timer?.invalidate() }
                .navigationTitle("Logs")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }

    }

    @MainActor
    private func load() {
        if let data = try? Data(contentsOf: url), let str = String(data: data, encoding: .utf8) {
            text = str
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                load()
            }
        }
    }
}
