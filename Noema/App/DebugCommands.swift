#if DEBUG
import SwiftUI
import UIKit

@MainActor
final class QuickStartDebugPresenter: NSObject, UIAdaptivePresentationControllerDelegate {
    static let shared = QuickStartDebugPresenter()
    private weak var presentedController: UIViewController?

    func presentQuickStart() async {
        if let controller = presentedController, controller.presentingViewController != nil {
            controller.dismiss(animated: true)
            presentedController = nil
            return
        }
        guard let root = topViewController() else { return }
        let host = UIHostingController(rootView: QuickStartView())
        host.modalPresentationStyle = .formSheet
        host.presentationController?.delegate = self
        root.present(host, animated: true)
        presentedController = host
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        presentedController = nil
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
