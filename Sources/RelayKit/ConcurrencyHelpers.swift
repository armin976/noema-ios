import Foundation

// Simple async semaphore to bound concurrent background work.
actor AsyncSemaphore {
    private var value: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) {
        self.value = max(1, value)
    }

    func acquire() async {
        if value > 0 {
            value -= 1
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            waiters.append(cont)
        }
    }

    func release() {
        if waiters.isEmpty {
            value += 1
        } else {
            let cont = waiters.removeFirst()
            cont.resume()
        }
    }
}

// Tracks identifiers currently being processed to avoid duplicate work
// when multiple polls overlap.
actor InFlightTracker<Key: Hashable> {
    private var set: Set<Key> = []

    func tryInsert(_ key: Key) -> Bool {
        if set.contains(key) { return false }
        set.insert(key)
        return true
    }

    func remove(_ key: Key) {
        set.remove(key)
    }
}

