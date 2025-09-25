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
        Group {
            if case let .running(description) = model.status.phase {
                HStack(spacing: 8) {
                    Text("AutoFlow:")
                        .font(.caption)
                        .bold()
                        .accessibilityHidden(true)
                    Text("Running \(description)")
                        .font(.caption2)
                        .lineLimit(1)
                        .accessibilityLabel("AutoFlow running \(description)")
                    Button(action: { model.stop() }) {
                        Text("Stop")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().stroke(Color.secondary, lineWidth: 1))
                    }
                    .accessibilityLabel("Stop AutoFlow")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.thinMaterial)
                .clipShape(Capsule())
                .accessibilityElement(children: .combine)
            }
        }
    }
}

#endif
