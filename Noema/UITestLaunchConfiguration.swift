import Foundation

enum UITestLaunchConfiguration {
    private static let fakeChatReadyKey = "UITEST_FAKE_CHAT_READY"
    private static let forceImageInputKey = "UITEST_FORCE_IMAGE_INPUT"
    private static let chatSendBehaviorKey = "UITEST_CHAT_SEND_BEHAVIOR"
    private static let fakeRemoteBackendID = UUID(uuidString: "8F9094E8-07A0-4B59-A487-59D0C17B8A9D")!

    static var isFakeChatReadyEnabled: Bool {
        isEnabled(fakeChatReadyKey)
    }

    static var isForceImageInputEnabled: Bool {
        isEnabled(forceImageInputKey)
    }

    @MainActor
    static func applyIfNeeded(modelManager: AppModelManager, chatVM: ChatVM) {
        if let chatSendBehavior = chatSendBehaviorOverride {
            UserDefaults.standard.set(chatSendBehavior.rawValue, forKey: ChatSendBehavior.storageKey)
        }

        if isForceImageInputEnabled {
            chatVM.supportsImageInput = true
        }

        guard isFakeChatReadyEnabled else { return }
        guard modelManager.activeRemoteSession == nil else { return }

        modelManager.activeRemoteSession = ActiveRemoteSession(
            backendID: fakeRemoteBackendID,
            backendName: "Noema",
            modelID: "ui-test-model",
            modelName: "Noema",
            endpointType: .noemaRelay,
            transport: .direct,
            streamingEnabled: true
        )
    }

    private static var chatSendBehaviorOverride: ChatSendBehavior? {
        guard let rawValue = ProcessInfo.processInfo.environment[chatSendBehaviorKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else {
            return nil
        }

        return ChatSendBehavior.from(rawValue)
    }

    private static func isEnabled(_ key: String) -> Bool {
        guard let rawValue = ProcessInfo.processInfo.environment[key] else {
            return false
        }

        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }
}
