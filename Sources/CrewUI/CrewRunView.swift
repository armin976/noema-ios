import SwiftUI
import Crew

public struct CrewRunLane: Identifiable, Equatable {
    public let id = UUID()
    public var role: String
    public var tasks: [String]
}

public struct CrewRunView: View {
    public var goal: String
    public var lanes: [CrewRunLane]
    public var budget: Counters
    public var onStop: (() -> Void)?
    public var onForceSynthesis: (() -> Void)?

    public init(goal: String, lanes: [CrewRunLane], budget: Counters, onStop: (() -> Void)? = nil, onForceSynthesis: (() -> Void)? = nil) {
        self.goal = goal
        self.lanes = lanes
        self.budget = budget
        self.onStop = onStop
        self.onForceSynthesis = onForceSynthesis
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text(goal).font(.title3).frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                VStack(alignment: .leading) {
                    Text("Tool calls: \(budget.toolCalls)")
                    Text("Tokens: \(budget.tokens)")
                    Text("Elapsed: \(Int(Date().timeIntervalSince(budget.started)))s")
                }
                Spacer()
                Button("Stop", action: { onStop?() })
                Button("Force Synthesis", action: { onForceSynthesis?() })
            }
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(lanes) { lane in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(lane.role).font(.headline)
                            ForEach(Array(lane.tasks.enumerated()), id: \.offset) { item in
                                Text("• \(item.element)")
                                    .font(.footnote)
                                    .padding(4)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(6)
                            }
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.3)))
                    }
                }
            }
            Spacer()
        }
        .padding()
        .navigationTitle("Crew Run")
    }
}

#Preview {
    CrewRunView(goal: "Explore dataset", lanes: [CrewRunLane(role: "Planner", tasks: ["Create plan", "Update plan"])], budget: Counters())
}
