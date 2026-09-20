import SwiftUI
import PhoebusCore
#if canImport(UIKit)
import UIKit
#endif

/// Root settings screen: lists Apollo's settings sections in its navigation shape.
/// Sections not yet implemented are shown disabled with an explanation rather than
/// removed.
public struct SettingsScreen: View {
    @Setting(AppLockSettings.self) private var appLockSettings
    let repository: RedditRepository
    let accountManager: AccountManager
    let onSignOut: () -> Void

    public init(repository: RedditRepository, accountManager: AccountManager, onSignOut: @escaping () -> Void) {
        self.repository = repository
        self.accountManager = accountManager
        self.onSignOut = onSignOut
    }

    /// Right-detail values on the root rows. Filters & Blocks has no value label,
    /// unlike App Icon ("Default") and Passcode ("Off").
    private func detailValue(for section: SettingsSection) -> String? {
        switch section {
        case .theme:
            return ThemeStore.load().isDark ? "Dark" : "Light"
        case .security:
            return appLockSettings.isEnabled ? "On" : "Off"
        case .accounts:
            return accountManager.accounts.count > 1 ? "\(accountManager.accounts.count) accounts" : nil
        default:
            return nil
        }
    }

    @State private var searchText = SettingsSearchDebugSeed.initialQuery
    /// The search field's bottom edge on screen, where the results start.
    @State private var searchFieldBottom: CGFloat = 0
    public var body: some View {
        crashTrackedBody.onAppear { CrashRecorder.record(.openedSettings) }
    }

    @ViewBuilder private var crashTrackedBody: some View {
        List {
            // The "Search Settings" field is pinned list content
            // rather than a `.searchable` modifier: on iOS 26 Liquid
            // Glass hands `.searchable`'s prompt to the tab bar's own
            // magnifying glass instead of showing a field under the
            // title. See `SettingsSearchFieldRow` for the geometry.
            Section {
                SettingsSearchFieldRow(text: $searchText)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: {
                        searchFieldBottom = $0
                    }
                    .modifier(ApolloFullBleedRowInsets(
                        bottom: ApolloSettingsRowMetrics.firstSectionTopPadding + 10.7))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .apolloListSectionSpacingZero()

            // Section 0: "Apollo Reborn", "Buy Us a Coffee". Saved
            // Categories / Translation / Tag Filters / Picture-in-Picture
            // are NOT root rows: Reborn splices them into General and
            // Filters & Blocks instead - see `GeneralSettingsScreen`
            // and `FiltersSettingsScreen`.
            Section {
                SettingsNavigationRow {
                    // The "Apollo Reborn" root row opens the full seven-section hub. The API key
                    // fields live in the hub's Setup -> Accounts & API Keys sub-screen.
                    ApolloRebornHubScreen(accountManager: accountManager)
                } label: {
                    // Reborn's artwork for its root row (`apollo-reborn-options-icon`).
                    SettingsIconRow(title: "Apollo Reborn", systemImage: "gearshape.2.fill", tint: .purple,
                                    artwork: StockArtwork.image("apollo-reborn-options-icon"))
                }
                .apolloSettingsRowInsets()
                SettingsNavigationRow {
                    BuyUsACoffeeScreen()
                } label: {
                    SettingsIconRow(title: "Buy Us a Coffee",
                                    systemImage: "cup.and.saucer.fill",
                                    tint: .yellow)
                }
                .apolloSettingsRowInsets()
            }

            // Section 2: Wallpapers, About.
            Section {
                SettingsNavigationRow {
                    WallpapersSettingsScreen()
                } label: {
                    // Row 0's accessory is a download glyph, not a chevron.
                    SettingsIconRow(title: "Wallpapers",
                                    systemImage: "photo.on.rectangle.angled",
                                    tint: .red,
                                    accessory: .download)
                }
                .apolloSettingsRowInsets()
                SettingsNavigationRow {
                    AboutScreen()
                } label: {
                    SettingsRow(section: .about)
                }
                .apolloSettingsRowInsets()
            }
        }
        // Results replace the settings list while searching, like UIKit's search-results
        // controller, keeping the root list's structure intact for when the search is
        // cancelled.
        .overlay {
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                GeometryReader { geo in
                SettingsSearchResultsList(
                    entries: SettingsSearch.results(for: searchText),
                    accountManager: accountManager,
                    repository: repository
                )
                .background(Color(.systemGroupedBackground))
                // Below the field wherever it is, so the field stays usable while results show (a
                // fixed offset covers it when the list is slightly scrolled).
                .padding(.top, max(0, searchFieldBottom - geo.frame(in: .global).minY + 8))
                }
            }
        }
        .apolloSettingsListAppearance()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayModeIfAvailable()
        // No right bar button: Reborn removes Apollo's legacy export
        // button here since it owns backup/restore in its own Data
        // section instead.
    }

    @ViewBuilder
    private func destination(for section: SettingsSection) -> some View {
        switch section {
        case .gestures:
            GestureSettingsScreen()
        case .markReadHiding:
            MarkReadSettingsScreen()
        case .appearance:
            AppearanceSettingsScreen()
        case .theme:
            ThemeSettingsScreen()
        case .about:
            AboutScreen()
        case .security:
            SecuritySettingsScreen()
        case .portraitLock:
            PortraitLockSettingsScreen()
        case .accounts:
            AccountManagerScreen(accountManager: accountManager)
        default:
            EmptyView()
        }
    }
}

/// Same tile+title row as `SettingsRow` below, for rows promoted onto the root
/// Settings list that aren't backed by a `SettingsSection` case (Apollo Reborn,
/// Buy Us a Coffee, Wallpapers).
struct SettingsIconRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.apolloTheme) private var apolloTheme
    let title: String
    let systemImage: String
    let tint: Color
    var accessory: SettingsRowAccessory = .chevron
    /// App Icon shows the selected icon's own artwork instead of an SF Symbol tile.
    var artwork: Image? = nil

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if let artwork {
                    artwork
                        .resizable()
                        .scaledToFill()
                        .frame(width: ApolloSettingsRowMetrics.tileSize,
                               height: ApolloSettingsRowMetrics.tileSize)
                        .clipShape(RoundedRectangle(
                            cornerRadius: ApolloSettingsRowMetrics.tileCornerRadius,
                            style: .continuous))
                } else {
                    SettingsTile(systemImage: systemImage, tint: tint)
                }
            }
            // Tile-to-title gap.
            .padding(.trailing, ApolloSettingsRowMetrics.tileToTitleGap)
            Text(title)
                .apolloFont(size: ApolloSettingsRowMetrics.titlePointSize)
                .foregroundStyle(Color.apolloPrimaryText(colorScheme: colorScheme, themeColors: apolloTheme))
                .lineLimit(1)
            Spacer(minLength: 8)
            accessory.view
        }
        // A 52pt row. Neither `defaultMinListRowHeight` (a minimum,
        // can't shrink) nor `.listRowInsets(...)` on the List achieves
        // this, since the row content sets its own height.
        .apolloSettingsRowHeight()
    }
}

/// The trailing accessory a root row draws for itself.
enum SettingsRowAccessory {
    case chevron
    case download

    @ViewBuilder var view: some View {
        switch self {
        case .chevron:
            ApolloSettingsChevron()
        case .download:
            Image(systemName: "arrow.down.to.line")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.tertiary)
        }
    }
}

/// Apollo's settings rows: a white glyph on a rounded per-row coloured tile, the
/// title, then a gray right-detail value (e.g. Theme -> "Light", App Icon ->
/// "Default", Face ID -> "Off") before the disclosure chevron.
struct SettingsRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.apolloTheme) private var apolloTheme
    let section: SettingsSection
    /// Overrides `section.title` where the row title depends on the device; only
    /// Passcode does.
    var title: String? = nil
    var detail: String?
    /// Artwork in place of the SF Symbol tile; only App Icon has any (see its call
    /// site in `SettingsScreen.body`).
    var artwork: Image? = nil

    var body: some View {
        HStack(spacing: 0) {
            let rgb = section.iconTintRGB
            Group {
                if let artwork {
                    artwork
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: ApolloSettingsRowMetrics.tileSize,
                               height: ApolloSettingsRowMetrics.tileSize)
                        .clipShape(RoundedRectangle(
                            cornerRadius: ApolloSettingsRowMetrics.tileCornerRadius,
                            style: .continuous))
                } else {
                    SettingsTile(systemImage: section.systemImage,
                                 tint: Color(red: rgb.red, green: rgb.green, blue: rgb.blue))
                }
            }
                .padding(.trailing, ApolloSettingsRowMetrics.tileToTitleGap)

            Text(title ?? section.title)
                .apolloFont(size: ApolloSettingsRowMetrics.titlePointSize)
                .foregroundStyle(section.isImplemented
                                 ? Color.apolloPrimaryText(colorScheme: colorScheme, themeColors: apolloTheme)
                                 : Color.apolloSecondaryText(colorScheme: colorScheme, themeColors: apolloTheme))
                // Title and right-detail stay on one line, shrinking rather than wrapping.
                .lineLimit(1)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            if let detail {
                Text(detail)
                    .apolloFont(size: ApolloSettingsRowMetrics.detailPointSize)
                    .foregroundStyle(Color(hex: ApolloSettingsRowMetrics.detailColorHex))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.trailing, 11)
            } else if let reason = section.disabledReason {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 150)
                    .padding(.trailing, 11)
            }

            ApolloSettingsChevron()
        }
        // Content height only. The row INSETS have to be applied by
        // the call site (see the `ForEach` in `SettingsScreen`),
        // because `.listRowInsets` only takes effect on a direct child
        // of the `List` and this view is a `NavigationLink`'s label.
        .apolloSettingsRowHeight()
    }
}

#if DEBUG
/// DEBUG-only seed for the Settings search field, so the searching state is
/// reachable without typing. Compiled out of release builds.
enum SettingsSearchDebugSeed {
    static var initialQuery: String {
        ProcessInfo.processInfo.environment["APOLLO_SETTINGS_SEARCH"] ?? ""
    }
}
#else
enum SettingsSearchDebugSeed {
    static var initialQuery: String { "" }
}
#endif

/// Full-colour PNGs in `StockIcons`.
enum StockArtwork {
    static func image(_ name: String) -> Image? {
        #if canImport(UIKit)
        guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "StockIcons"),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        return Image(uiImage: image)
        #else
        return nil
        #endif
    }
}
