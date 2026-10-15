import SwiftUI
import PhoebusCore
#if canImport(UIKit)
import UIKit
#endif

/// Reborn's "Copy Widget Setup Code" row (section "Extras"). The widgets read
/// the feed and sign-in from the shared App Group (`SharedFeedCache`), so the
/// copied code is a JSON description of this install's widget configuration,
/// not a decoder for Apollo's own setup codes.
///
/// The Status section says whether this install's signing lets the
/// widgets work; see `docs/widgets-and-signing.md`.
struct WidgetSetupSections: View {
    @State private var didCopy = false

    var body: some View {
        Group {
            Section {
                LabeledContent("App Group", value: sharing.appGroupAvailable ? "Available" : "Not granted")
                LabeledContent("Sign-in for Widgets", value: credentialsSummary)
                LabeledContent("Editable Widgets", value: sharing.mismatchedAppID == nil ? "Available" : "Blocked by signing")
            } header: {
                Text("Widget")
                    .apolloSectionHeader()
            } footer: {
                Text(statusFooter)
                    .apolloSectionFooter()
            }
            Section {
                Text(setupCodeJSON)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
                    .apolloPlainSettingsRowInsets()

                Button(didCopy ? "Copied" : "Copy Widget Setup Code") {
                    copyToPasteboard(setupCodeJSON)
                    didCopy = true
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .tint(.accentColor)
                // search: item "Widget Setup"
                .apolloSearchRow("Copy Widget Setup Code", lastBeforeFooter: true)
            } header: {
                Text("Widget Setup Code")
                    .apolloSectionHeader()
            } footer: {
                Text("Copy a code to set up the Phoebus home-screen widget.")
                    .apolloSectionFooter()
            }
        }
    }

    private var sharing: SharedFeedCache.SharingStatus { SharedFeedCache.sharingStatus }

    private var credentialsSummary: String {
        guard let credentials = SharedFeedCache.loadCredentials() else { return "Not shared" }
        if credentials.hasFreshBearer || credentials.canRefreshBearer { return "OAuth" }
        return credentials.hasCookie ? "Web session" : "Expired"
    }

    private var statusFooter: String {
        if let appID = sharing.mismatchedAppID {
            return "This install was signed as \(appID) but is installed as \(Bundle.main.bundleIdentifier ?? "another app"), so iOS won't give Post, Feed, Photo, Calendar, or Headline their settings and they stay blank. Re-sign with the bundle identifier set to \(appID) (in Feather: Identifier)."
        }
        if sharing.appGroupAvailable {
            return "Widgets read your feed and sign-in through the App Group. Open the Home feed once after installing so they have something to show."
        }
        return "This install's signing grants no App Group, so the widgets can't read your feed or sign-in and only show public subreddits."
    }

    private var setupCodeJSON: String {
        let payload: [String: Any] = [
            "appGroupID": sharing.appGroup,
            "appGroupAvailable": sharing.appGroupAvailable,
            "signedAppID": sharing.mismatchedAppID ?? "matches bundle",
            "widgetSignIn": credentialsSummary,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    private func copyToPasteboard(_ string: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = string
        #endif
    }
}
