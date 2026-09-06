#if canImport(UIKit)
import SwiftUI
import UIKit
import PhoebusCore

/// Reborn's crash prompt: when the app becomes active with a report it
/// hasn't offered yet, ask once whether to review it. Waits for the app's
/// own interface, and skips an activation where something else is already
/// presented so the report waits for the next.
@MainActor
final class CrashPromptCoordinator: NSObject {
    static let shared = CrashPromptCoordinator()
    private var presenting = false
    private var observer: NSObjectProtocol?

    func start() {
        guard CrashManager.shared.isInstalled, observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { CrashPromptCoordinator.shared.applicationDidBecomeActive() }
            }
    }

    private var promptedIDs: [Int64] {
        (UserDefaults.standard.array(forKey: CrashCaptureSettings.promptedReportIDsKey) as? [NSNumber])?.map(\.int64Value) ?? []
    }

    /// Pruned to reports that still exist, so the list can't grow.
    private func markPrompted(_ id: Int64) {
        let pending = Set(CrashManager.shared.pendingReportIDs)
        var prompted = promptedIDs.filter { pending.contains($0) }
        if !prompted.contains(id) { prompted.append(id) }
        UserDefaults.standard.set(prompted.map { NSNumber(value: $0) }, forKey: CrashCaptureSettings.promptedReportIDsKey)
    }

    private func applicationDidBecomeActive() {
        guard !presenting, let latest = CrashManager.shared.pendingReportIDs.last,
              !promptedIDs.contains(latest) else { return }
        presenting = true
        attempt(id: latest, retry: 0)
    }

    private func attempt(id: Int64, retry: Int) {
        guard let root = Self.rootViewController, root.view.window != nil else {
            if retry < 10 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.attempt(id: id, retry: retry + 1) }
            } else {
                presenting = false
            }
            return
        }
        var presenter = root
        while let presented = presenter.presentedViewController, !presented.isBeingDismissed,
              !(presented is UIAlertController) {
            presenter = presented
        }
        guard presenter.presentedViewController == nil else { presenting = false; return }
        presentAlert(id: id, from: presenter)
    }

    private static var rootViewController: UIViewController? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?.keyWindow?.rootViewController
    }

    private func presentAlert(id: Int64, from presenter: UIViewController) {
        guard let report = CrashManager.shared.report(id: id) else {
            CrashManager.shared.delete(id: id)
            presenting = false
            return
        }
        let message = report.category == "memory_termination"
            ? "Phoebus appears to have been terminated because of memory pressure the last time you used it. A technical report was saved on this device and may help fix the problem.\n\nNothing is sent unless you choose to share it."
            : "Phoebus unexpectedly closed the last time you used it. A technical crash report was saved on this device and may help fix the problem.\n\nNothing is sent unless you choose to share it."
        let alert = UIAlertController(title: "Uh oh! Phoebus encountered a problem", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Review & Report", style: .default) { _ in
            self.markPrompted(id)
            self.presentReview(report, from: presenter)
        })
        alert.addAction(UIAlertAction(title: "Not Now", style: .cancel) { _ in
            self.markPrompted(id)
            self.presenting = false
        })
        alert.addAction(UIAlertAction(title: "Delete Report", style: .destructive) { _ in
            self.markPrompted(id)
            self.confirmDelete(id: id, from: presenter)
        })
        presenter.present(alert, animated: true)
    }

    private func presentReview(_ report: PendingCrashReport, from presenter: UIViewController) {
        weak var host: UIViewController?
        let review = NavigationStack {
            CrashReviewScreen(report: report) {
                host?.dismiss(animated: true)
                CrashPromptCoordinator.shared.presenting = false
            }
        }
        let controller = UIHostingController(rootView: review)
        controller.modalPresentationStyle = .formSheet
        controller.presentationController?.delegate = self
        host = controller
        presenter.present(controller, animated: true)
    }

    private func confirmDelete(id: Int64, from presenter: UIViewController) {
        let confirm = UIAlertController(title: "Delete Crash Report?",
                                        message: "The report only exists on this device. This can't be undone.",
                                        preferredStyle: .alert)
        confirm.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            CrashManager.shared.delete(id: id)
            self.presenting = false
        })
        confirm.addAction(UIAlertAction(title: "Keep", style: .cancel) { _ in self.presenting = false })
        presenter.present(confirm, animated: true)
    }
}

extension CrashPromptCoordinator: UIAdaptivePresentationControllerDelegate {
    /// Swiping the review sheet away keeps the report, as "Not Now".
    nonisolated func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        MainActor.assumeIsolated { presenting = false }
    }
}
#endif
