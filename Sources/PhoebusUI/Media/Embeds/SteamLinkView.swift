import SwiftUI
import PhoebusCore
#if canImport(UIKit)
import UIKit
#endif

/// Renders a Steam store post as an "Open in Steam" card (Reborn's Steam
/// deep-link support): tapping hands off to the `steam://` scheme, falling back
/// to the store page in Safari if Steam isn't installed (iOS does this for an
/// unregistered scheme via `openURL`'s completion).
public struct SteamLinkView: View {
    let kind: SteamURLParser.ItemKind
    let id: String
    @Environment(\.openURL) private var openURL

    public init(kind: SteamURLParser.ItemKind, id: String) {
        self.kind = kind
        self.id = id
    }

    public var body: some View {
        Button {
            openInSteam()
        } label: {
            HStack {
                Image(systemName: "gamecontroller.fill")
                Text("Open in Steam")
                Spacer()
                Image(systemName: "arrow.up.forward")
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    /// Goes straight to the system, not the app's `openURL`, which routes links
    /// through Phoebus's own handling and would swallow the hand-off. Tries the
    /// store's Universal Link first (as Reborn does), then `steam://`, then the
    /// store page.
    private func openInSteam() {
        #if canImport(UIKit)
        guard let web = fallbackWebURL else { return }
        UIApplication.shared.open(web, options: [.universalLinksOnly: true]) { opened in
            guard !opened else { return }
            guard let native = SteamURLParser.nativeAppURL(kind: kind, id: id) else { openURL(web); return }
            UIApplication.shared.open(native) { opened in
                if !opened { openURL(web) }
            }
        }
        #else
        if let fallbackWebURL { openURL(fallbackWebURL) }
        #endif
    }

    private var fallbackWebURL: URL? {
        switch kind {
        case .app: return URL(string: "https://store.steampowered.com/app/\(id)")
        case .sub: return URL(string: "https://store.steampowered.com/sub/\(id)")
        }
    }
}
