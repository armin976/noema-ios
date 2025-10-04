import SwiftUI
import Foundation

struct RemoteBackendRow: View {
    let backend: RemoteBackend
    let isFetching: Bool
    let isOffline: Bool

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private var status: (text: String, color: Color)? {
        if let error = backend.lastError, !error.isEmpty {
            return (error, .red)
        }
        if let fetched = backend.lastFetched {
            let relative = Self.relativeFormatter.localizedString(for: fetched, relativeTo: Date())
            return ("Updated \(relative)", Color.secondary)
        }
        if backend.cachedModels.isEmpty {
            return ("No models fetched yet", Color.secondary)
        }
        return nil
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(backend.name)
                        .fontWeight(.semibold)
                    badge(text: backend.endpointType.displayName,
                          color: badgeColor(for: backend.endpointType))
                    if backend.hasAuth {
                        badge(text: "Auth", color: .orange)
                    }
                }
                Text(backend.displayBaseHost)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let status {
                    Text(status.text)
                        .font(.caption2)
                        .foregroundColor(status.color)
                        .lineLimit(2)
                }
            }
            Spacer()
            if isOffline {
                Label("Offline", systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if isFetching {
                ProgressView()
            } else if backend.cachedModels.isEmpty {
                Text("Tap to load")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(backend.cachedModels.count) models")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor.opacity(0.2)))
            }
        }
        .padding(.vertical, 6)
    }

    private func badge(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundColor(color)
    }

    private func badgeColor(for type: RemoteBackend.EndpointType) -> Color {
        switch type {
        case .openAI: return .blue
        case .lmStudio: return .purple
        case .ollama: return .green
        }
    }
}
