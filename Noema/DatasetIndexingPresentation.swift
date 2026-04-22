import Foundation

struct DatasetIndexingPresentation: Equatable {
    enum ActionState: Equatable {
        case none
        case startAndCancel
        case cancelOnly
    }

    enum Tone: Equatable {
        case active
        case success
        case failure
    }

    let title: String
    let shortTitle: String
    let message: String
    let progressText: String
    let systemImage: String
    let actionState: ActionState
    let tone: Tone
    let showsProgressBar: Bool

    var isTerminal: Bool {
        tone != .active
    }

    static func make(
        for status: DatasetProcessingStatus,
        locale: Locale = LocalizationManager.preferredLocale()
    ) -> DatasetIndexingPresentation {
        let title = title(for: status.stage, locale: locale)
        let shortTitle = shortTitle(for: status.stage, locale: locale)
        let message = (status.message?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? (status.message ?? title)
            : title

        switch status.stage {
        case .completed:
            return DatasetIndexingPresentation(
                title: title,
                shortTitle: shortTitle,
                message: message,
                progressText: String(localized: "Ready", locale: locale),
                systemImage: "checkmark.circle.fill",
                actionState: .none,
                tone: .success,
                showsProgressBar: false
            )
        case .failed:
            return DatasetIndexingPresentation(
                title: title,
                shortTitle: shortTitle,
                message: message,
                progressText: String(localized: "Error", locale: locale),
                systemImage: "exclamationmark.triangle.fill",
                actionState: .none,
                tone: .failure,
                showsProgressBar: false
            )
        case .embedding where status.progress <= 0.0001:
            return DatasetIndexingPresentation(
                title: title,
                shortTitle: shortTitle,
                message: message,
                progressText: progressText(for: status, locale: locale),
                systemImage: "sparkles",
                actionState: .startAndCancel,
                tone: .active,
                showsProgressBar: true
            )
        case .embedding:
            return DatasetIndexingPresentation(
                title: title,
                shortTitle: shortTitle,
                message: message,
                progressText: progressText(for: status, locale: locale),
                systemImage: "sparkles",
                actionState: .cancelOnly,
                tone: .active,
                showsProgressBar: true
            )
        case .extracting:
            return DatasetIndexingPresentation(
                title: title,
                shortTitle: shortTitle,
                message: message,
                progressText: progressText(for: status, locale: locale),
                systemImage: "doc.text.magnifyingglass",
                actionState: .cancelOnly,
                tone: .active,
                showsProgressBar: true
            )
        case .compressing:
            return DatasetIndexingPresentation(
                title: title,
                shortTitle: shortTitle,
                message: message,
                progressText: progressText(for: status, locale: locale),
                systemImage: "text.line.first.and.arrowtriangle.forward",
                actionState: .cancelOnly,
                tone: .active,
                showsProgressBar: true
            )
        }
    }

    static func title(for stage: DatasetProcessingStage, locale: Locale = LocalizationManager.preferredLocale()) -> String {
        switch stage {
        case .extracting:
            return String(localized: "Extracting", locale: locale)
        case .compressing:
            return String(localized: "Compressing", locale: locale)
        case .embedding:
            return String(localized: "Embedding", locale: locale)
        case .completed:
            return String(localized: "Ready", locale: locale)
        case .failed:
            return String(localized: "Failed", locale: locale)
        }
    }

    static func shortTitle(for stage: DatasetProcessingStage, locale: Locale = LocalizationManager.preferredLocale()) -> String {
        switch stage {
        case .extracting:
            return String(localized: "Extract", locale: locale)
        case .compressing:
            return String(localized: "Compress", locale: locale)
        case .embedding:
            return String(localized: "Embed", locale: locale)
        case .completed:
            return String(localized: "Done", locale: locale)
        case .failed:
            return String(localized: "Error", locale: locale)
        }
    }

    static func progressText(
        for status: DatasetProcessingStatus,
        locale: Locale = LocalizationManager.preferredLocale()
    ) -> String {
        let percentage = Int(max(0, min(1, status.progress)) * 100)
        return String.localizedStringWithFormat(
            String(localized: "%d%% · %@", locale: locale),
            percentage,
            etaText(status.etaSeconds, locale: locale)
        )
    }

    static func etaText(_ etaSeconds: Double?, locale: Locale = LocalizationManager.preferredLocale()) -> String {
        guard let etaSeconds, etaSeconds > 0 else {
            return String(localized: "…", locale: locale)
        }
        return String.localizedStringWithFormat(
            String(localized: "~%dm %02ds", locale: locale),
            Int(etaSeconds) / 60,
            Int(etaSeconds) % 60
        )
    }
}
