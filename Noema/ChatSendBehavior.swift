import Foundation

enum ChatSendBehavior: String, CaseIterable, Identifiable {
    case keyboardToolbarSend = "keyboard_toolbar_send"
    case returnKeySends = "return_key_sends"

    static let storageKey = "chatSendBehavior"
    static let defaultValue: ChatSendBehavior = .keyboardToolbarSend

    var id: String { rawValue }

    static func from(_ rawValue: String) -> ChatSendBehavior {
        ChatSendBehavior(rawValue: rawValue) ?? .defaultValue
    }

    var titleKey: String {
        switch self {
        case .keyboardToolbarSend:
            return "Return Inserts New Line"
        case .returnKeySends:
            return "Return Key Sends"
        }
    }

    var settingsDescriptionKey: String {
        switch self {
        case .keyboardToolbarSend:
            return "Return inserts a new line. Use the Send button to send."
        case .returnKeySends:
            return "Return sends your message instead of inserting a new line."
        }
    }

    var accessibilityHintKey: String {
        switch self {
        case .keyboardToolbarSend:
            return "Return inserts a new line. Use Command-Return or the Send button to send."
        case .returnKeySends:
            return "Return sends your message."
        }
    }
}
