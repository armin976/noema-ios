import Foundation

public enum AutoFlowRule: Sendable {
    case datasetQuickEDA
    case cleanHighNulls
    case addPlots
}

public struct AutoFlowRuleContext: Sendable {
    public let preferences: AutoFlowPreferences
    public let now: Date
    public let guardNullThreshold: Double

    public init(preferences: AutoFlowPreferences, now: Date = Date(), guardNullThreshold: Double = 0.3) {
        self.preferences = preferences
        self.now = now
        self.guardNullThreshold = guardNullThreshold
    }
}

public enum AutoFlowRuleEngine {
    static func action(for event: AutoFlowEvent, context: AutoFlowRuleContext) -> AutoFlowAction? {
        switch event {
        case let .datasetMounted(dataset):
            guard context.preferences.profile != .off,
                  context.preferences.toggles.quickEDAOnMount,
                  dataset.sizeMB <= 50 else {
                return nil
            }
            let description = "Running Quick EDA on \(dataset.url.lastPathComponent)"
            let play = AutoFlowAction.Playbook(identifier: "eda-basic",
                                               dataset: dataset.url,
                                               parameters: [:],
                                               description: description)
            return AutoFlowAction(playbook: play, cacheKey: cacheKey(for: "datasetMounted", dataset: dataset.url))
        case let .runFinished(run):
            return handleRunFinished(run, context: context)
        case .appBecameActive, .errorOccurred:
            return nil
        }
    }

    private static func handleRunFinished(_ run: AutoFlowRunEvent,
                                          context: AutoFlowRuleContext) -> AutoFlowAction? {
        let profile = context.preferences.profile
        let toggles = context.preferences.toggles
        guard profile != .off else { return nil }

        if toggles.cleanOnHighNulls,
           run.stats.nullPercentage >= context.guardNullThreshold,
           profile == .balanced || profile == .aggressive {
            let description = "Cleaning high nulls"
            let play = AutoFlowAction.Playbook(identifier: "clean-profile",
                                               dataset: run.stats.dataset,
                                               parameters: [:],
                                               description: description)
            return AutoFlowAction(playbook: play,
                                  cacheKey: cacheKey(for: "clean-high-nulls", dataset: run.stats.dataset))
        }

        if toggles.plotsOnMissing,
           profile == .aggressive,
           !run.stats.madeImages {
            var params: [String: String] = [:]
            if !run.stats.artifacts.contains("plots") {
                params["mode"] = "plots"
            }
            let description = "Adding plots"
            let play = AutoFlowAction.Playbook(identifier: "eda-basic",
                                               dataset: run.stats.dataset,
                                               parameters: params,
                                               description: description)
            return AutoFlowAction(playbook: play,
                                  cacheKey: cacheKey(for: "missing-plots", dataset: run.stats.dataset))
        }

        return nil
    }

    private static func cacheKey(for rule: String, dataset: URL?) -> String {
        let datasetComponent = dataset?.absoluteString ?? "global"
        return "\(rule)::\(datasetComponent)"
    }
}
