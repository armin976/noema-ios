import Foundation

enum RelayConfiguration {
    static var containerIdentifier: String {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "CloudKitContainerIdentifier") as? String else {
            assertionFailure("Missing CloudKitContainerIdentifier entry in Info.plist")
            return ""
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            assertionFailure("CloudKitContainerIdentifier is empty")
        }
        return trimmed
    }

    static var hostDeviceIdentifier: String {
        let defaults = UserDefaults.standard
        let key = "relay.hostDeviceIdentifier"
        if let existing = defaults.string(forKey: key), !existing.isEmpty {
            let canonical = existing.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if canonical != existing {
                defaults.set(canonical, forKey: key)
            }
            return canonical
        }
        let identifier = UUID().uuidString.uppercased()
        defaults.set(identifier, forKey: key)
        return identifier
    }
}
