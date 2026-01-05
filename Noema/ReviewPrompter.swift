// ReviewPrompter.swift
// Centralized, throttled in‑app review trigger with milestone tracking.

import Foundation
#if canImport(StoreKit)
import StoreKit
#endif
#if canImport(UIKit)
import UIKit
#endif

@MainActor
enum ReviewGate {
    static let minDaysBetweenPrompts = 90
    static let minDaysBetweenAttempts = 7   // if the sheet didn’t appear or was dismissed
    static let minSessionsBeforeFirstPrompt = 5

    static let minWebSearchUsesForPrompt = 5
    static let minRemoteUsesForPrompt = 1

    static func shouldPrompt(now: Date = .now,
                             sessions: Int,
                             lastPromptDate: Date?,
                             lastAttemptDate: Date?,
                             milestones: ReviewPrompter.Milestones) -> Bool {
        guard sessions >= minSessionsBeforeFirstPrompt else { return false }
        if let last = lastPromptDate {
            let days = Calendar.current.dateComponents([.day], from: last, to: now).day ?? 0
            if days < minDaysBetweenPrompts { return false }
        }
        if let lastTry = lastAttemptDate {
            let days = Calendar.current.dateComponents([.day], from: lastTry, to: now).day ?? 0
            if days < minDaysBetweenAttempts { return false }
        }

        // Milestone logic: sessions + (RAG used after embed) OR (remote used) OR (web search used several times)
        let ragQualified = (milestones.datasetEmbeddedCount > 0 && milestones.ragUsedCount > 0)
        let remoteQualified = milestones.remoteUsedCount >= minRemoteUsesForPrompt
        let webQualified = milestones.webSearchUsedCount >= minWebSearchUsesForPrompt
        return ragQualified || remoteQualified || webQualified
    }
}

@MainActor
final class ReviewPrompter {
    static let shared = ReviewPrompter()

    struct Milestones {
        var datasetEmbeddedCount: Int
        var ragUsedCount: Int
        var webSearchUsedCount: Int
        var remoteUsedCount: Int
    }

    private let d = UserDefaults.standard
    // Keys
    private enum Key {
        static let lastPromptDate = "review.lastPromptDate"
        static let lastAttemptDate = "review.lastAttemptDate"
        static let sessionCount = "review.sessionCount"
        static let ragUsedCount = "review.ragUsedCount"
        static let datasetEmbeddedCount = "review.datasetEmbeddedCount"
        static let webSearchUsedCount = "review.webSearchUsedCount"
        static let remoteUsedCount = "review.remoteUsedCount"
    }

    // Session tracking
    func trackSession() {
        let c = d.integer(forKey: Key.sessionCount)
        d.set(c + 1, forKey: Key.sessionCount)
    }

    // Milestone counters
    func noteRAGUsed() {
        let c = d.integer(forKey: Key.ragUsedCount)
        d.set(c + 1, forKey: Key.ragUsedCount)
    }

    func noteDatasetEmbedded() {
        let c = d.integer(forKey: Key.datasetEmbeddedCount)
        d.set(c + 1, forKey: Key.datasetEmbeddedCount)
    }

    func noteWebSearchUsed() {
        let c = d.integer(forKey: Key.webSearchUsedCount)
        d.set(c + 1, forKey: Key.webSearchUsedCount)
    }

    func noteRemoteUsed() {
        let c = d.integer(forKey: Key.remoteUsedCount)
        d.set(c + 1, forKey: Key.remoteUsedCount)
    }

    // Public API: attempt a prompt if the app is idle and user met milestones
    func safeMaybePromptIfEligible(chatVM: ChatVM?) {
        // Don’t show if actively generating or dataset processing banner is up
        if let vm = chatVM {
            if vm.isStreaming { return }
            if vm.injectionStage != .none { return }
            if vm.stillLoading || vm.loading { return }
        }
        // Don’t prompt if app is not in foreground
        #if canImport(UIKit)
        if UIApplication.shared.applicationState != .active { return }
        #endif
        maybePrompt()
    }

    func maybePrompt() {
        let sessions = d.integer(forKey: Key.sessionCount)
        let lastDate = d.object(forKey: Key.lastPromptDate) as? Date
        let lastAttempt = d.object(forKey: Key.lastAttemptDate) as? Date
        let milestones = Milestones(
            datasetEmbeddedCount: d.integer(forKey: Key.datasetEmbeddedCount),
            ragUsedCount: d.integer(forKey: Key.ragUsedCount),
            webSearchUsedCount: d.integer(forKey: Key.webSearchUsedCount),
            remoteUsedCount: d.integer(forKey: Key.remoteUsedCount)
        )
        guard ReviewGate.shouldPrompt(sessions: sessions,
                                      lastPromptDate: lastDate,
                                      lastAttemptDate: lastAttempt,
                                      milestones: milestones) else { return }
        d.set(Date(), forKey: Key.lastAttemptDate)
        requestReviewIfAppropriate()
    }

    // MARK: - StoreKit bridge
    #if canImport(StoreKit) && canImport(UIKit) && !os(visionOS)
    private func requestReviewIfAppropriate() {
        guard let scene = UIApplication.shared
            .connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        SKStoreReviewController.requestReview(in: scene)
        d.set(Date(), forKey: Key.lastPromptDate)
    }
    #else
    private func requestReviewIfAppropriate() { /* noop on non‑iOS */ }
    #endif

    // MARK: - Fallback deep link (Settings entry point)
    func openWriteReviewPageIfAvailable() {
        guard let appID = Bundle.main.infoDictionary?["AppStoreID"] as? String,
              !appID.isEmpty else { return }
        #if canImport(UIKit)
        let url = URL(string: "https://apps.apple.com/app/id\(appID)?action=write-review")!
        UIApplication.shared.open(url)
        #endif
    }
}

