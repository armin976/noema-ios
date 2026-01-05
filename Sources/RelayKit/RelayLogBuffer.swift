import Foundation

// Background buffer that coalesces log events and flushes them to
// the main-actor RelayLogStore in batches to avoid pegging Thread 1.
actor RelayLogBuffer {
    static let shared = RelayLogBuffer()

    // Tunables. Keep fairly snappy, but not per-line.
    // Cadence driven by user-tunable config
    private func flushIntervalLive() -> TimeInterval { RelayPerformanceConfig.liveFlushInterval() }
    private func flushIntervalIdle() -> TimeInterval { RelayPerformanceConfig.idleFlushInterval() }
    private let maxBatch: Int = 250                     // cap per flush to bound UI work

    private var pending: [RelayLogEntry] = []
    private var flushTask: Task<Void, Never>?

    func enqueue(_ entry: RelayLogEntry) async {
        pending.append(entry)
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        let interval = effectiveInterval()
        flushTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            if interval > 0 { try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000)) }
            await self.flush()
        }
    }

    private func effectiveInterval() -> TimeInterval {
        // If we can read gate state, use the faster cadence when active.
        // Avoid querying MainActor here; rely on the 'live' interval which
        // itself is conservative and user-tunable.
        return flushIntervalLive()
    }

    private func flush() async {
        guard !pending.isEmpty else {
            flushTask = nil
            return
        }
        let batch = Array(pending.prefix(maxBatch))
        pending.removeFirst(batch.count)
        await MainActor.run {
            // Drop quickly when console is not active.
            if RelayConsoleGate.isActive {
                RelayLogStore.shared.appendBatch(batch)
            }
        }
        // If more remains, schedule another short flush; otherwise clear task.
        if !pending.isEmpty {
            flushTask = nil
            scheduleFlush()
        } else {
            flushTask = nil
        }
    }
}
