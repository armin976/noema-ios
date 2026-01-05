import Foundation
import RelayKit

#if os(iOS) || os(visionOS)
actor RelayOutbox {
    private var configuredContainerID: String?
    private let pollIntervalNanoseconds: UInt64 = 750_000_000 // 0.75s
    private let timeout: TimeInterval = 90

    func sendAndAwaitReply(
        containerID: String,
        conversationID: UUID,
        history: [(role: String, text: String, fullText: String?)],
        parameters: [String: String]
    ) async throws -> RelayEnvelope {
        guard !containerID.isEmpty else {
            throw InferenceError.notConfigured
        }
        if configuredContainerID != containerID {
            CloudKitRelay.shared.configure(containerIdentifier: containerID, provider: nil)
            configuredContainerID = containerID
        }
        let messages = history.map { entry in
            let visible = RelayMessage.visibleText(from: entry.text)
            let full = entry.fullText ?? entry.text
            return RelayMessage(conversationID: conversationID,
                                role: entry.role,
                                text: visible,
                                fullText: full)
        }
        let envelope = RelayEnvelope(
            conversationID: conversationID,
            messages: messages,
            needsResponse: true,
            parameters: parameters
        )
        try await CloudKitRelay.shared.postFromiOS(envelope)
        return try await waitForReply(conversationID: conversationID, baselineCount: messages.count)
    }

    private func waitForReply(conversationID: UUID, baselineCount: Int) async throws -> RelayEnvelope {
        var deadline = Date().addingTimeInterval(timeout)
        var lastStatus: RelayStatus?
        while Date() < deadline {
            try Task.checkCancellation()
            if let envelope = try await CloudKitRelay.shared.fetchEnvelope(conversationID: conversationID) {
                let status = envelope.status
                if status == .failed {
                    throw InferenceError.other(envelope.errorMessage ?? "Relay processing failed")
                }
                if (status == .acknowledged || status == .processing),
                   status != lastStatus {
                    deadline = Date().addingTimeInterval(timeout)
                }
                lastStatus = status

                if (!envelope.needsResponse && envelope.messages.count > baselineCount) || status == .completed {
                    return envelope
                }
            }
            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
        throw InferenceError.other("Timed out waiting for relay response")
    }
}
#endif
