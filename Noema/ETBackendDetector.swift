import Foundation

enum ETBackendDetector {
    static let anyBackendLabel = "Any"

    static func detect(tags: [String], modelName: String) -> ETBackend? {
        let normalizedTags = tags.map { $0.lowercased() }
        let normalizedName = modelName.lowercased()

        let xnnpackSignals = ["xnnpack"]
        let coremlSignals = ["coreml", "core-ml", "ane"]
        let mpsSignals = ["mps", "metal"]

        let hasXNNPACK = containsAnySignal(in: normalizedTags, name: normalizedName, signals: xnnpackSignals)
        let hasCoreML = containsAnySignal(in: normalizedTags, name: normalizedName, signals: coremlSignals)
        let hasMPS = containsAnySignal(in: normalizedTags, name: normalizedName, signals: mpsSignals)

        let matches: [ETBackend] = [
            hasXNNPACK ? .xnnpack : nil,
            hasCoreML ? .coreml : nil,
            hasMPS ? .mps : nil,
        ].compactMap { $0 }

        guard matches.count == 1 else { return nil }
        return matches[0]
    }

    static func allowedBackends() -> [ETBackend] {
        if DeviceGPUInfo.supportsGPUOffload {
            return ETBackend.allCases
        }
        return [.xnnpack]
    }

    static func effectiveBackend(userSelected: ETBackend?, detected: ETBackend?) -> ETBackend {
        let allowed = Set(allowedBackends())
        if let userSelected, allowed.contains(userSelected) {
            return userSelected
        }
        if let detected, allowed.contains(detected) {
            return detected
        }
        return .xnnpack
    }

    static func recommendedBackendLabel(tags: [String], modelName: String) -> String {
        guard let detected = detect(tags: tags, modelName: modelName) else { return anyBackendLabel }
        return detected.displayName
    }

    private static func containsAnySignal(in tags: [String], name: String, signals: [String]) -> Bool {
        for signal in signals {
            if name.contains(signal) { return true }
            if tags.contains(where: { $0 == signal || $0.contains(signal) }) { return true }
        }
        return false
    }
}
