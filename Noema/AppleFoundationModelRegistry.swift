import Foundation

final class AppleFoundationModelRegistry: ModelRegistry, @unchecked Sendable {
    static let modelID = "apple/system-foundation-model"
    static let modelName = "Apple Foundation Model"
    static let quantLabel = "System"
    static let parameterCountLabel = "3B params"

    private var record: ModelRecord {
        ModelRecord(
            id: Self.modelID,
            displayName: Self.modelName,
            publisher: "Apple",
            summary: String(localized: "On-device Apple Foundation language model."),
            parameterCountLabel: Self.parameterCountLabel,
            hasInstallableQuant: true,
            formats: [.afm],
            installed: true,
            tags: ["on-device", "apple-intelligence"],
            pipeline_tag: "text-generation",
            minRAMBytes: nil,
            recommendedETBackend: nil,
            supportsVision: false
        )
    }

    private var details: ModelDetails {
        ModelDetails(
            id: Self.modelID,
            summary: String(localized: "On-device Apple Foundation language model."),
            parameterCountLabel: Self.parameterCountLabel,
            quants: [
                QuantInfo(
                    label: Self.quantLabel,
                    format: .afm,
                    sizeBytes: 0,
                    downloadURL: URL(string: "afm://system")!,
                    sha256: nil,
                    configURL: nil
                )
            ],
            promptTemplate: nil,
            minRAMBytes: nil
        )
    }

    func curated() async throws -> [ModelRecord] {
        guard AppleFoundationModelAvailability.isSupportedDevice else { return [] }
        return [record]
    }

    func searchStream(
        query: String,
        page: Int,
        format: ModelFormat?,
        includeVisionModels: Bool,
        visionOnly: Bool
    ) -> AsyncThrowingStream<ModelRecord, Error> {
        AsyncThrowingStream { continuation in
            guard AppleFoundationModelAvailability.isSupportedDevice else {
                continuation.finish()
                return
            }
            guard !visionOnly else {
                continuation.finish()
                return
            }
            if let format, format != .afm {
                continuation.finish()
                return
            }

            let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if needle.isEmpty || matches(query: needle, record: record) {
                continuation.yield(record)
            }
            continuation.finish()
        }
    }

    func details(for id: String) async throws -> ModelDetails {
        guard AppleFoundationModelAvailability.isSupportedDevice, id == Self.modelID else {
            throw URLError(.badURL)
        }
        return details
    }

    private func matches(query: String, record: ModelRecord) -> Bool {
        if record.displayName.lowercased().contains(query) { return true }
        if record.id.lowercased().contains(query) { return true }
        if record.publisher.lowercased().contains(query) { return true }
        return false
    }
}
