#if DEBUG
import SwiftUI
import UIKit

struct DebugCommands: Commands {
    var body: some Commands {
        CommandMenu("Debug") {
            Button("Run Self-Test") {
                Task { await DebugSelfTestPresenter.shared.runSelfTest() }
            }
        }
    }
}

@MainActor
final class DebugSelfTestPresenter: NSObject, UIDocumentInteractionControllerDelegate {
    static let shared = DebugSelfTestPresenter()
    private var controller: UIDocumentInteractionController?

    func runSelfTest() async {
        let runner = SelfTestRunner()
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
