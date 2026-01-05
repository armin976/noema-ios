import Foundation

#if os(iOS) || os(visionOS)
import Network
#endif

actor LocalNetworkPermissionRequester {
    static let shared = LocalNetworkPermissionRequester()

#if os(iOS) || os(visionOS)
    private let defaultsKey = "Noema.LocalNetworkPermissionRequested"
    private var hasPrompted: Bool
    private var isRequesting = false
#endif

    private init() {
#if os(iOS) || os(visionOS)
        hasPrompted = UserDefaults.standard.bool(forKey: defaultsKey)
#endif
    }

    func ensurePrompt() async {
#if os(iOS) || os(visionOS)
        guard !hasPrompted, !isRequesting else { return }

        isRequesting = true
        defer { isRequesting = false }

        await logger.log("[LocalNetwork] Requesting local network permission probe")

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let browser = NWBrowser(for: .bonjour(type: "_noema-permission._tcp", domain: nil), using: params)
            let queue = DispatchQueue(label: "Noema.LocalNetworkPermission")

            final class ResumeState: @unchecked Sendable {
                private let lock = NSLock()
                private var didResume = false

                func tryResume(canceling browser: NWBrowser? = nil) -> Bool {
                    lock.lock()
                    defer { lock.unlock() }
                    guard !didResume else { return false }
                    didResume = true
                    browser?.cancel()
                    return true
                }
            }

            let resumeState = ResumeState()

            browser.stateUpdateHandler = { [resumeState] state in
                switch state {
                case .failed(let error):
                    Task { await logger.log("[LocalNetwork] Permission probe failed: \(error.localizedDescription)") }
                    if resumeState.tryResume(canceling: browser) {
                        continuation.resume()
                    }
                case .cancelled:
                    if resumeState.tryResume() {
                        continuation.resume()
                    }
                default:
                    break
                }
            }

            browser.start(queue: queue)

            queue.asyncAfter(deadline: .now() + 1.5) { [resumeState] in
                if resumeState.tryResume(canceling: browser) {
                    continuation.resume()
                }
            }
        }

        hasPrompted = true
        UserDefaults.standard.set(true, forKey: defaultsKey)
#else
        return
#endif
    }
}
