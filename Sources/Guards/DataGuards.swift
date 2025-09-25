import Foundation
import NoemaCore

public struct GuardMetrics: Sendable, Equatable {
    public let nullPercentage: Double
    public let duplicateRatio: Double
    public let constantColumns: [String]

    public init(nullPercentage: Double, duplicateRatio: Double, constantColumns: [String]) {
        self.nullPercentage = nullPercentage
        self.duplicateRatio = duplicateRatio
        self.constantColumns = constantColumns
    }
}

public actor DataGuardEngine {
    public static let shared = DataGuardEngine()

    private let eventBus: AutoFlowEventBus
    private let fileManager: FileManager

    public init(eventBus: AutoFlowEventBus = .shared, fileManager: FileManager = .default) {
        self.eventBus = eventBus
        self.fileManager = fileManager
    }

    public func run(on datasetURL: URL, madeImages: Bool) async throws -> GuardMetrics {
        let metrics = try computeMetrics(for: datasetURL)
        try writeReport(for: datasetURL, metrics: metrics)
        let stats = AutoFlowRunEvent.Stats(dataset: datasetURL,
                                           artifacts: ["GuardReport.md"],
                                           nullPercentage: metrics.nullPercentage,
                                           madeImages: madeImages)
        await eventBus.publish(.runFinished(AutoFlowRunEvent(stats: stats)))
        return metrics
    }

    public func process(datasetIDs: [String], madeImages: Bool) async {
        guard let firstID = datasetIDs.first, let url = resolveDatasetURL(for: firstID) else { return }
        do {
            _ = try await run(on: url, madeImages: madeImages)
        } catch {
            await eventBus.publish(.errorOccurred(AppError(code: .autoFlow, message: error.localizedDescription)))
        }
    }

    private func computeMetrics(for url: URL) throws -> GuardMetrics {
        let data = try String(contentsOf: url)
        let lines = data.split(whereSeparator: { $0.isNewline })
        guard let headerLine = lines.first else {
            return GuardMetrics(nullPercentage: 0, duplicateRatio: 0, constantColumns: [])
        }
        let header = parseCSVRow(String(headerLine))
        let sampleLimit = min(lines.count - 1, 500)
        var rows: [[String]] = []
        if sampleLimit > 0 {
            for index in 1...sampleLimit {
                let line = lines[index]
                let parsed = parseCSVRow(String(line))
                rows.append(pad(row: parsed, count: header.count))
            }
        }
        let totalCells = rows.count * header.count
        var nullCount = 0
        var duplicateTracker: Set<String> = []
        var duplicateHits = 0
        var columnValues: [Int: Set<String>] = [:]
        for row in rows {
            let key = row.joined(separator: "|\u{1F}" )
            if !duplicateTracker.insert(key).inserted {
                duplicateHits += 1
            }
            for (index, value) in row.enumerated() {
                if value.isEmpty || value.lowercased() == "na" || value.lowercased() == "null" {
                    nullCount += 1
                }
                columnValues[index, default: []].insert(value)
            }
        }
        let nullPercentage = totalCells > 0 ? Double(nullCount) / Double(totalCells) : 0
        let duplicateRatio = rows.isEmpty ? 0 : Double(duplicateHits) / Double(rows.count)
        var constantColumns: [String] = []
        for (index, column) in header.enumerated() {
            if columnValues[index, default: []].count <= 1 {
                constantColumns.append(column)
            }
        }
        return GuardMetrics(nullPercentage: nullPercentage,
                            duplicateRatio: duplicateRatio,
                            constantColumns: constantColumns)
    }

    private func writeReport(for datasetURL: URL, metrics: GuardMetrics) throws {
        let directory = datasetURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let reportURL = directory.appendingPathComponent("GuardReport.md")
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        let nullText = formatter.string(from: metrics.nullPercentage as NSNumber) ?? String(format: "%.2f", metrics.nullPercentage)
        let duplicateText = formatter.string(from: metrics.duplicateRatio as NSNumber) ?? String(format: "%.2f", metrics.duplicateRatio)
        let constants = metrics.constantColumns.isEmpty ? "None" : metrics.constantColumns.joined(separator: ", ")
        let report = """
        # Data Guard Report
        - Null percentage: \(nullText)
        - Duplicate ratio: \(duplicateText)
        - Constant columns: \(constants)
        """
        try report.write(to: reportURL, atomically: true, encoding: .utf8)
    }

    private func resolveDatasetURL(for id: String) -> URL? {
        var root = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        root = root?.appendingPathComponent("Datasets", isDirectory: true).appendingPathComponent(id)
        return root
    }

    private func parseCSVRow(_ line: String) -> [String] {
        line.split(separator: ",", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private func pad(row: [String], count: Int) -> [String] {
        if row.count >= count { return Array(row.prefix(count)) }
        var padded = row
        padded.append(contentsOf: Array(repeating: "", count: count - row.count))
        return padded
    }
}
