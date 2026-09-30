import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit

/// Presents the system document picker in copy mode and hands back a
/// local copy of the picked file.
///
/// Used instead of SwiftUI's `.fileImporter` for backup restores, which
/// opens files in place: a backup in iCloud Drive or another provider
/// that has not been downloaded leaves the picker on screen. Copy mode
/// makes the system fetch the file first and always dismisses the
/// picker, and presenting from the topmost controller keeps it clear of
/// SwiftUI's own presentations (the "Restore Settings" confirmation
/// dialog).
@MainActor
enum DocumentImportPicker {
    private final class Delegate: NSObject, UIDocumentPickerDelegate {
        let completion: (Result<URL, Error>?) -> Void
        init(completion: @escaping (Result<URL, Error>?) -> Void) { self.completion = completion }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            finish(urls.first.map { .success($0) })
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            finish(nil)
        }

        private func finish(_ result: Result<URL, Error>?) {
            DocumentImportPicker.active = nil
            completion(result)
        }
    }

    /// The picker only holds its delegate weakly.
    private static var active: Delegate?

    /// - Parameter completion: `nil` when the user cancels.
    static func present(types: [UTType], completion: @escaping (Result<URL, Error>?) -> Void) {
        guard let presenter = topController() else { return }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = false
        let delegate = Delegate(completion: completion)
        active = delegate
        picker.delegate = delegate
        presenter.present(picker, animated: true)
    }

    private static func topController() -> UIViewController? {
        var top = UIKitTree.keyWindow?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}

extension View {
    /// `.fileImporter`'s shape, backed by `DocumentImportPicker`.
    func apolloDocumentImporter(isPresented: Binding<Bool>, allowedContentTypes: [UTType],
                                onCompletion: @escaping (Result<URL, Error>) -> Void) -> some View {
        onChange(of: isPresented.wrappedValue) { _, shown in
            guard shown else { return }
            // Reset now, not on completion: a swipe-dismissed picker may not
            // report a cancel, and a flag left true would make the next tap a
            // no-op.
            isPresented.wrappedValue = false
            // After the tapped control's own presentation (a
            // confirmation dialog) has finished dismissing.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                DocumentImportPicker.present(types: allowedContentTypes) { result in
                    if let result { onCompletion(result) }
                }
            }
        }
    }
}
#else
extension View {
    func apolloDocumentImporter(isPresented: Binding<Bool>, allowedContentTypes: [UTType],
                                onCompletion: @escaping (Result<URL, Error>) -> Void) -> some View {
        fileImporter(isPresented: isPresented, allowedContentTypes: allowedContentTypes, onCompletion: onCompletion)
    }
}
#endif
