import SwiftUI

/// Stores developer-facing feature toggles backed by ``UserDefaults``.
///
/// These flags are not exposed to end users, but they let internal builds
/// enable experimental functionality such as the Inspector panel.
struct InternalFlags {
    @AppStorage("inspectorEnabled") var inspectorEnabled = false
}
