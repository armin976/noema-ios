#if canImport(SwiftUI)
import SwiftUI

@MainActor
public final class AutoFlowHUDModel: ObservableObject {
    @Published public private(set) var status: AutoFlowStatus = AutoFlowStatus()
    private var task: Task<Void, Never>?
    private let engine: AutoFlowEngine

    public init(engine: AutoFlowEngine = .shared) {
        self.engine = engine
        subscribe()
    }

    deinit {
        task?.cancel()
    }

    private func subscribe() {
        task = Task { [weak self] in
            guard let self else { return }
            let stream = await engine.subscribeStatus()
            for await value in stream { await self.update(status: value) }
        }
    }

    private func update(status: AutoFlowStatus) async {
        await MainActor.run { self.status = status }
    }

    func stop() {
        Task { await engine.stop() }
    }
}

public struct AutoFlowHUD: View {
    @ObservedObject private var model: AutoFlowHUDModel

    public init(model: AutoFlowHUDModel = AutoFlowHUDModel()) {
        self.model = model
    }

    public var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("AutoFlow")
                    .font(.caption)
                    .bold()
                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Button(action: { model.stop() }) {
                Text("Stop")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().stroke(Color.secondary, lineWidth: 1))
            }
            .accessibilityLabel("Stop AutoFlow")
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AutoFlow status: \(statusText)")
    }

    private var statusText: String {
        switch model.status.phase {
        case .idle:
            return "Idle"
        case .evaluating:
            return "Evaluating"
        case let .running(description):
            return description
        case let .paused(reason):
            return reason
        case .blocked:
            return "Blocked"
        }
    }

    private var statusColor: Color {
        switch model.status.phase {
        case .running:
            return .green
        case .paused:
            return .orange
        case .blocked:
            return .red
        case .idle, .evaluating:
            return .blue
        }
    }
}

#endif
