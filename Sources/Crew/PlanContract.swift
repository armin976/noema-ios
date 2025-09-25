import Foundation

public struct Budgets: Codable, Equatable, Sendable {
    public var wallClockSec: Int
    public var maxToolCalls: Int
    public var maxTokensTotal: Int

    public init(wallClockSec: Int, maxToolCalls: Int, maxTokensTotal: Int) {
        self.wallClockSec = wallClockSec
        self.maxToolCalls = maxToolCalls
        self.maxTokensTotal = maxTokensTotal
    }
}

public struct Deliverable: Codable, Equatable, Sendable {
    public var name: String
    public var type: String

    public init(name: String, type: String) {
        self.name = name
        self.type = type
    }
}

public enum QualityRule: Codable, Equatable, Sendable {
    case minImages(Int)
    case tableHasCols(table: String, cols: [String])
    case maxNullPct(column: String, pct: Double)

    private enum CodingKeys: String, CodingKey {
        case kind
        case intValue
        case table
        case cols
        case column
        case pct
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .minImages(let count):
            try container.encode("minImages", forKey: .kind)
            try container.encode(count, forKey: .intValue)
        case .tableHasCols(let table, let cols):
            try container.encode("tableHasCols", forKey: .kind)
            try container.encode(table, forKey: .table)
            try container.encode(cols, forKey: .cols)
        case .maxNullPct(let column, let pct):
            try container.encode("maxNullPct", forKey: .kind)
            try container.encode(column, forKey: .column)
            try container.encode(pct, forKey: .pct)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "minImages":
            let count = try container.decode(Int.self, forKey: .intValue)
            self = .minImages(count)
        case "tableHasCols":
            let table = try container.decode(String.self, forKey: .table)
            let cols = try container.decode([String].self, forKey: .cols)
            self = .tableHasCols(table: table, cols: cols)
        case "maxNullPct":
            let column = try container.decode(String.self, forKey: .column)
            let pct = try container.decode(Double.self, forKey: .pct)
            self = .maxNullPct(column: column, pct: pct)
        default:
            self = .minImages(0)
        }
    }
}

public struct QualityGate: Codable, Equatable, Sendable {
    public var name: String
    public var rule: QualityRule

    public init(name: String, rule: QualityRule) {
        self.name = name
        self.rule = rule
    }
}

public struct PlanContract: Codable, Equatable, Sendable {
    public var goal: String
    public var allowedTools: [String]
    public var requiredDeliverables: [Deliverable]
    public var budgets: Budgets
    public var qualityGates: [QualityGate]

    public init(goal: String,
                allowedTools: [String],
                requiredDeliverables: [Deliverable],
                budgets: Budgets,
                qualityGates: [QualityGate]) {
        self.goal = goal
        self.allowedTools = allowedTools
        self.requiredDeliverables = requiredDeliverables
        self.budgets = budgets
        self.qualityGates = qualityGates
    }
}

