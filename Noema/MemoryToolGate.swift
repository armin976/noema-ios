import Foundation

struct MemoryToolGate {
    static func isAvailable(currentFormat: ModelFormat? = nil) -> Bool {
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: "memoryEnabled") as? Bool ?? true
        guard enabled else { return false }

        let isRemote = defaults.object(forKey: "currentModelIsRemote") as? Bool ?? false
        guard !isRemote else { return false }

        let supportsFunctionCalling = defaults.object(forKey: "currentModelSupportsFunctionCalling") as? Bool ?? false
        guard supportsFunctionCalling else { return false }

        return true
    }
}
