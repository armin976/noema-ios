import Foundation

struct MemoryPromptBudgetStatus: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case inactive
        case allLoaded
        case partiallyLoaded
        case notLoaded
    }

    enum Reason: Equatable, Sendable {
        case contextBudget
    }

    let state: State
    let loadedCount: Int
    let totalCount: Int
    let omittedCount: Int
    let isActive: Bool
    let reason: Reason?

    static let inactive = MemoryPromptBudgetStatus(
        state: .inactive,
        loadedCount: 0,
        totalCount: 0,
        omittedCount: 0,
        isActive: false,
        reason: nil
    )

    var shouldDisplayNotice: Bool {
        isActive && totalCount > 0 && (state == .partiallyLoaded || state == .notLoaded)
    }
}

struct MemoryPromptBudgetPlan: Equatable, Sendable {
    let entries: [MemoryEntry]
    let status: MemoryPromptBudgetStatus

    var snapshot: String? {
        guard !entries.isEmpty else { return nil }
        return MemoryStore.promptSnapshot(entries: entries)
    }
}

enum MemoryPromptBudgeter {
    static func prioritizedEntries(from entries: [MemoryEntry]) -> [MemoryEntry] {
        entries.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    static func plan(
        entries: [MemoryEntry],
        isActive: Bool,
        promptTokenLimit: Int,
        basePromptTokens: Int,
        estimatePromptTokens: ([MemoryEntry]) -> Int
    ) -> MemoryPromptBudgetPlan {
        guard isActive else {
            return MemoryPromptBudgetPlan(entries: [], status: .inactive)
        }

        let prioritized = prioritizedEntries(from: entries)
        guard !prioritized.isEmpty else {
            return MemoryPromptBudgetPlan(
                entries: [],
                status: MemoryPromptBudgetStatus(
                    state: .allLoaded,
                    loadedCount: 0,
                    totalCount: 0,
                    omittedCount: 0,
                    isActive: true,
                    reason: nil
                )
            )
        }

        guard basePromptTokens < promptTokenLimit else {
            return MemoryPromptBudgetPlan(
                entries: [],
                status: MemoryPromptBudgetStatus(
                    state: .notLoaded,
                    loadedCount: 0,
                    totalCount: prioritized.count,
                    omittedCount: prioritized.count,
                    isActive: true,
                    reason: .contextBudget
                )
            )
        }

        var included: [MemoryEntry] = []
        for entry in prioritized {
            let candidate = included + [entry]
            if estimatePromptTokens(candidate) <= promptTokenLimit {
                included = candidate
            }
        }

        let loadedCount = included.count
        let totalCount = prioritized.count
        let omittedCount = max(0, totalCount - loadedCount)
        let state: MemoryPromptBudgetStatus.State = {
            if loadedCount == 0 { return .notLoaded }
            if loadedCount == totalCount { return .allLoaded }
            return .partiallyLoaded
        }()

        return MemoryPromptBudgetPlan(
            entries: included,
            status: MemoryPromptBudgetStatus(
                state: state,
                loadedCount: loadedCount,
                totalCount: totalCount,
                omittedCount: omittedCount,
                isActive: true,
                reason: state == .allLoaded ? nil : .contextBudget
            )
        )
    }
}
