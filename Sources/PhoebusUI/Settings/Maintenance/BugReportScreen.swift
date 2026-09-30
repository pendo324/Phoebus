import SwiftUI
import PhoebusCore
#if canImport(WebKit) && canImport(UIKit)
import WebKit
import UIKit
#endif

/// The "Bug Reports" destination from the Apollo Reborn hub: a `WKWebView`
/// titled "Bug Report" opening a new issue on Phoebus's GitHub repo, with the
/// app and iOS versions filled in, and a thin progress bar under the
/// navigation bar.
public struct BugReportScreen: View {
    /// GitHub's new-issue form for the repo.
    static let reportURL = "https://github.com/pendo324/Phoebus/issues/new"

    @State private var progress: Double = 0

    public init() {}

    /// The issue body, prefilled with the versions.
    static func formURL() -> URL? {
        var components = URLComponents(string: reportURL)
        var version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        if version.hasPrefix("v") { version.removeFirst() }
        #if canImport(UIKit)
        let iosVersion = UIDevice.current.systemVersion
        #else
        let iosVersion = ProcessInfo.processInfo.operatingSystemVersionString
        #endif
        components?.queryItems = [
            URLQueryItem(name: "body", value: "**What happened:**\n\n\n**Steps to reproduce:**\n\n\n---\nPhoebus \(version), iOS \(iosVersion)"),
        ]
        return components?.url
    }

    public var body: some View {
        VStack(spacing: 0) {
            // `UIProgressView` pinned to the safe-area top, the bar under the nav bar.
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .opacity(progress < 1 ? 1 : 0)
            #if canImport(WebKit) && canImport(UIKit)
            BugReportWebView(url: Self.formURL(), progress: $progress)
            #else
            Text("Bug reporting requires WebKit.")
            #endif
        }
        .navigationTitle("Bug Report")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if canImport(WebKit) && canImport(UIKit)
private struct BugReportWebView: UIViewRepresentable {
    let url: URL?
    @Binding var progress: Double

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // The default store, so a GitHub sign-in persists.
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.observe(webView)
        if let url {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            webView.load(request)
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(progress: $progress) }

    /// `estimatedProgress` KVO for the progress bar.
    final class Coordinator: NSObject {
        private let progress: Binding<Double>
        private weak var webView: WKWebView?
        init(progress: Binding<Double>) { self.progress = progress }
        func observe(_ webView: WKWebView) {
            self.webView = webView
            webView.addObserver(self, forKeyPath: "estimatedProgress", options: [.new], context: nil)
        }
        deinit { webView?.removeObserver(self, forKeyPath: "estimatedProgress") }
        override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                                   change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
            guard keyPath == "estimatedProgress",
                  let value = change?[.newKey] as? Double else { return }
            DispatchQueue.main.async { [progress] in progress.wrappedValue = value }
        }
    }
}
#endif
