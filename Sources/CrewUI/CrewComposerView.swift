import SwiftUI
import Crew

public struct CrewComposerView: View {
    @State private var goal: String
    @State private var selectedDatasets: Set<String>
    public var availableDatasets: [String]
    public var contractPreview: PlanContract
    public var onRun: (String, [String]) -> Void

    public init(goal: String = "",
                availableDatasets: [String] = [],
                contractPreview: PlanContract,
                onRun: @escaping (String, [String]) -> Void) {
        _goal = State(initialValue: goal)
        _selectedDatasets = State(initialValue: [])
        self.availableDatasets = availableDatasets
        self.contractPreview = contractPreview
        self.onRun = onRun
    }

    public var body: some View {
        Form {
            Section(header: Text("Goal")) {
                TextField("Describe what the crew should accomplish", text: $goal)
            }
            Section(header: Text("Datasets")) {
                if availableDatasets.isEmpty {
                    Text("No local datasets available").foregroundColor(.secondary)
                } else {
                    ForEach(availableDatasets, id: \.self) { dataset in
                        Toggle(isOn: Binding(
                            get: { selectedDatasets.contains(dataset) },
                            set: { isOn in
                                if isOn { selectedDatasets.insert(dataset) } else { selectedDatasets.remove(dataset) }
                            }
                        )) {
                            Text(dataset)
                        }
                    }
                }
            }
            Section(header: Text("Contract")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(contractPreview.goal).font(.headline)
                    Text("Allowed tools: \(contractPreview.allowedTools.joined(separator: ", "))")
                        .font(.footnote)
                    Text("Budgets: time \(contractPreview.budgets.wallClockSec)s, tool calls \(contractPreview.budgets.maxToolCalls), tokens \(contractPreview.budgets.maxTokensTotal)")
                        .font(.footnote)
                    if contractPreview.requiredDeliverables.isEmpty == false {
                        VStack(alignment: .leading) {
                            Text("Deliverables").font(.subheadline)
                            ForEach(contractPreview.requiredDeliverables, id: \.name) { deliverable in
                                Text("• \(deliverable.name) (\(deliverable.type))").font(.footnote)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                Button("Run Crew") {
                    onRun(goal, Array(selectedDatasets))
                }
                .disabled(goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("Crew Composer")
    }
}

#Preview {
    CrewComposerView(contractPreview: PlanContract(goal: "Explore", allowedTools: ["python.execute"], requiredDeliverables: [], budgets: Budgets(wallClockSec: 120, maxToolCalls: 6, maxTokensTotal: 10_000), qualityGates: [])) { _, _ in }
}
