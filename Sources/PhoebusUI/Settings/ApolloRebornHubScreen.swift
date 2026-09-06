import SwiftUI
import UniformTypeIdentifiers
import PhoebusCore
#if canImport(UIKit)
import UIKit
#endif

/// Reborn's "Apollo Reborn" settings hub, with its seven sections in order:
/// Setup, Features, Shortcuts, Data, Advanced, Privacy, About.
///
/// Reborn's flat form is the *Accounts & API Keys* sub-screen the Setup section
/// discloses to. Section titles, footers, row order, titles, SF Symbol names and
/// tile colors follow Reborn.
public struct ApolloRebornHubScreen: View {
    let accountManager: AccountManager
    public init(accountManager: AccountManager) {
        self.accountManager = accountManager
    }

    public var body: some View {
        List {
        }
        .apolloSettingsListAppearance()
        // Offsets the hub header's -21 top pull so the first header cap sits where
        // Apollo's does.
        .safeAreaPadding(.top, 7)
        .navigationTitle("Apollo Reborn")
        .navigationBarTitleDisplayModeIfAvailable()
    }
}
/// Shared colored-tile glyph used by every hub row: a 29x29 rounded rect at
/// cornerRadius 6 holding a white 16pt medium symbol.
struct SettingsTile: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ApolloSettingsRowMetrics.tileCornerRadius,
                             style: .continuous)
                .fill(tint)
            Image(systemName: systemImage)
                .font(.system(size: ApolloSettingsRowMetrics.tileGlyphPointSize,
                              weight: ApolloSettingsRowMetrics.tileGlyphWeight))
                .foregroundStyle(.white)
        }
        .frame(width: ApolloSettingsRowMetrics.tileSize,
               height: ApolloSettingsRowMetrics.tileSize)
    }
}
