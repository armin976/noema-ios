// UsageLimiterDemo.swift
import SwiftUI

struct UsageLimiterDemoView: View {
    @State private var status: String = ""
    @State private var remainingCount: Int = 0
    private let limiter: UsageLimiter

    init() {
        let config = UsageLimiterConfig(service: "com.noema.usagelimiter.demo", account: "search", appGroupID: "group.com.noema")
        self.limiter = try! UsageLimiter(config: config)
        _remainingCount = State(initialValue: limiter.remaining())
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Remaining: \(remainingCount)")
            Button("Consume") {
                do {
                    let result = try limiter.consume()
                    switch result {
                    case .consumed:
                        status = "Consumed"
                    case .throttledCooldown(let until):
                        status = "Cooldown until: \(until.formatted())"
                    case .limitReached(let until):
                        status = "Limit reached. Try again: \(until.formatted())"
                    }
                } catch {
                    status = "Error: \(error.localizedDescription)"
                }
                remainingCount = limiter.remaining()
            }
            .buttonStyle(.borderedProminent)
            Text(status)
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}


