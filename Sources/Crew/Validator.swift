import Foundation

public struct Validator {
    public init() {}

    public static func failures(_ gates: [QualityGate], bb: Blackboard) async -> [String] {
        var failures: [String] = []
        for gate in gates {
            switch gate.rule {
            case .minImages(let count):
                let artifacts = await bb.artifacts { $0.type == .imagePNG }
                if artifacts.count < count {
                    failures.append("Gate \(gate.name) failed: requires >= \(count) images")
                }
            case .tableHasCols(let table, let cols):
                let artifacts = await bb.artifacts { $0.name == table }
                guard let artifact = artifacts.first else {
                    failures.append("Gate \(gate.name) failed: missing table \(table)")
                    continue
                }
                if let data = try? Data(contentsOf: URL(fileURLWithPath: artifact.path)),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    let keys = Set(json.first?.keys.map { $0 } ?? [])
                    let missing = cols.filter { !keys.contains($0) }
                    if !missing.isEmpty {
                        failures.append("Gate \(gate.name) failed: missing columns \(missing.joined(separator: ", "))")
                    }
                } else {
                    failures.append("Gate \(gate.name) failed: unreadable table artifact")
                }
            case .maxNullPct(let column, let pct):
                let facts = await bb.facts { $0.key == "metric:\(column)" }
                guard let fact = facts.first,
                      let ratio = try? JSONDecoder().decode(Double.self, from: fact.value) else {
                    failures.append("Gate \(gate.name) failed: missing metric for \(column)")
                    continue
                }
                if ratio > pct {
                    failures.append("Gate \(gate.name) failed: null ratio \(ratio) > \(pct)")
                }
            }
        }
        return failures
    }
}
