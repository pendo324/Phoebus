import SwiftUI
import PhoebusCore
#if canImport(UIKit)
import UIKit
#endif

/// The root settings screen: one pinned search field, then the thirteen
/// settings categories, each a coloured tile row opening its category
/// screen.
public struct SettingsScreen: View {
    let repository: RedditRepository
    let accountManager: AccountManager

    public init(repository: RedditRepository, accountManager: AccountManager) {
        self.repository = repository
        self.accountManager = accountManager
    }

    /// Right-detail values on the root rows: the active theme, the
    /// passcode state, the signed-in account count and the version.
    private var categoryValues: SettingsCategoryValues {
        SettingsCategoryValues(
            accountCount: accountManager.accounts.count,
            version: "v" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
        )
    }

    @Environment(\.settingsSignOut) private var signOut

    /// The conditions rows exist under here, by the tags the index names
    /// them with.
    private var searchAvailable: Set<String> {
        Set(SettingsRowRequirement.available(signOut: signOut).map(\.rawValue))
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

            Section {
                ForEach(SettingsCategory.allCases) { category in
                    SettingsNavigationRow {
                        SettingsCategoryScreen(category: category, accountManager: accountManager)
                    } label: {
                        let rgb = category.tintRGB
                        SettingsCategoryRow(
                            title: category.title,
                            subtitle: category.subtitle,
                            systemImage: category.systemImage,
                            tint: Color(red: rgb.red, green: rgb.green, blue: rgb.blue),
                            detail: category.trailingValue(categoryValues)
                        )
                    }
                    .apolloSettingsRowInsets()
                }
            }
        }
        // Results replace the settings list while searching, like UIKit's search-results
        // controller, keeping the root list's structure intact for when the search is
        // cancelled.
        .overlay {
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                GeometryReader { geo in
                SettingsSearchResultsList(
                    // Update rows exist only in builds with a release channel.
                    entries: SettingsSearch.results(for: searchText, available: searchAvailable),
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
        // button here; backup and restore are Data & Storage rows.
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
