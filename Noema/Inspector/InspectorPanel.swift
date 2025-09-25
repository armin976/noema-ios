import Combine
import SwiftUI
import UIKit

/// Core Inspector content with tabbed navigation.
struct InspectorPanel: View {
    enum Tab: String, CaseIterable, Identifiable {
        case artifacts
        case logs

        var id: String { rawValue }

        var title: String {
            switch self {
            case .artifacts: return "Artifacts"
            case .logs: return "Logs"
            }
        }

        var iconName: String {
            switch self {
            case .artifacts: return "tray.full"
            case .logs: return "terminal"
            }
        }
    }

    @Binding var selection: Tab

    @State private var artifacts: [ArtifactsDataSource.Entry] = []
    @State private var isLoadingArtifacts = false

    private let dataSource = ArtifactsDataSource()

    var body: some View {
        VStack(spacing: 0) {
            pickerBar
            Divider()
            Group {
                switch selection {
                case .artifacts:
                    ArtifactsTabView(
                        entries: artifacts,
                        isLoading: isLoadingArtifacts
                    )
                case .logs:
                    LogsTabView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground).opacity(0.01))
        }
        .onAppear { handleAppear() }
        .onChange(of: selection) { newValue in
            if newValue == .artifacts { loadArtifacts() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pythonExecutionDidComplete)) { _ in
            if selection == .artifacts {
                loadArtifacts()
            }
        }
    }

    private var pickerBar: some View {
        HStack(spacing: 12) {
            Picker("Inspector Tab", selection: $selection) {
                ForEach(Tab.allCases) { tab in
                    Label(tab.title, systemImage: tab.iconName)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)

            if selection == .artifacts {
                Button {
                    loadArtifacts(force: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reload Artifacts")
                .disabled(isLoadingArtifacts)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func handleAppear() {
        if selection == .artifacts && artifacts.isEmpty {
            loadArtifacts()
        }
    }

    private func loadArtifacts(force: Bool = false) {
        if isLoadingArtifacts && !force { return }
        isLoadingArtifacts = true
        Task.detached { [dataSource] in
            let entries = dataSource.loadEntries()
            await MainActor.run {
                self.artifacts = entries
                self.isLoadingArtifacts = false
            }
        }
    }
}

// MARK: - Artifacts Tab

private struct ArtifactsTabView: View {
    let entries: [ArtifactsDataSource.Entry]
    let isLoading: Bool

    private let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if isLoading {
                    ProgressView("Loading artifacts…")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                } else if entries.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .imageScale(.large)
                            .foregroundStyle(.secondary)
                        Text("No cached artifacts found")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Execute a Python tool to populate this list.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 60)
                } else {
                    ForEach(entries) { entry in
                        artifactSection(for: entry)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    @ViewBuilder
    private func artifactSection(for entry: ArtifactsDataSource.Entry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.id)
                        .font(.headline)
                    Text(entry.formattedDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if !entry.tables.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tables")
                        .font(.subheadline.weight(.semibold))
                    ForEach(entry.tables) { table in
                        ScrollView(.horizontal, showsIndicators: true) {
                            Text(table.preview)
                                .font(.system(.footnote, design: .monospaced))
                                .multilineTextAlignment(.leading)
                                .padding(12)
                        }
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }

            if !entry.figures.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Figures")
                        .font(.subheadline.weight(.semibold))
                    ForEach(entry.figures) { figure in
                        if let image = UIImage(contentsOfFile: figure.url.path) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color(.separator), lineWidth: 0.5)
                                )
                        } else {
                            HStack {
                                Image(systemName: "photo")
                                Text(figure.id)
                                    .font(.footnote)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }

            if !entry.attachments.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Attachments")
                        .font(.subheadline.weight(.semibold))
                    ForEach(entry.attachments) { attachment in
                        HStack {
                            Image(systemName: "doc")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading) {
                                Text(attachment.id)
                                    .font(.footnote)
                                Text(byteFormatter.string(fromByteCount: Int64(attachment.byteCount)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 0.5)
        )
    }
}

// MARK: - Logs Tab

private struct LogsTabView: View {
    @State private var logText = ""
    @State private var timer: Timer?
    @State private var bottomAnchor = UUID()

    private let logURL = logger.logFileURL

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(logText)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .id(bottomAnchor)
            }
            .background(Color(.systemBackground))
            .onAppear {
                load(proxy: proxy)
                startTimer(proxy: proxy)
            }
            .onDisappear {
                timer?.invalidate()
            }
        }
    }

    private func load(proxy: ScrollViewProxy) {
        if let data = try? Data(contentsOf: logURL),
           let string = String(data: data, encoding: .utf8) {
            logText = string
            bottomAnchor = UUID()
            scrollToBottom(proxy: proxy)
        }
    }

    private func startTimer(proxy: ScrollViewProxy) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async {
                load(proxy: proxy)
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        }
    }
}
