#if DEBUG
import SwiftUI
import UIKit

struct DebugCommands: Commands {
    var body: some Commands {
        CommandMenu("Debug") {
            Button("Run Self-Check") {
                Task { await DebugSelfCheckPresenter.shared.runSelfCheck() }
            }
        }
    }
}

@MainActor
final class DebugSelfCheckPresenter: NSObject, UIDocumentInteractionControllerDelegate {
    static let shared = DebugSelfCheckPresenter()
    private var controller: UIDocumentInteractionController?

    func runSelfCheck() async {
        let runner = SelfCheckRunner()
        let result = await runner.runAll()
        presentReport(at: result.reportURL)
    }

    private func presentReport(at url: URL) {
        controller = UIDocumentInteractionController(url: url)
        controller?.delegate = self
        controller?.presentPreview(animated: true)
    }

    func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
        topViewController() ?? UIViewController()
    }

    private func topViewController(from root: UIViewController? = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first(where: { $0.isKeyWindow })?.rootViewController) -> UIViewController? {
        if let nav = root as? UINavigationController {
            return topViewController(from: nav.visibleViewController)
        } else if let tab = root as? UITabBarController {
            return topViewController(from: tab.selectedViewController)
        } else if let presented = root?.presentedViewController {
            return topViewController(from: presented)
        }
        return root
    }
}
#endif
