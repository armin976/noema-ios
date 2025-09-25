import Foundation

extension Notification.Name {
    static let debugChatRequested = Notification.Name("DebugChatRequested")
}

#if DEBUG
import SwiftUI

struct DebugChatCommand: Commands {
    var body: some Commands {
        CommandGroup(after: .debugging) {
            Button("Open Chat Screen") {
                NotificationCenter.default.post(name: .debugChatRequested, object: nil)
            }
        }
    }
}
#endif
