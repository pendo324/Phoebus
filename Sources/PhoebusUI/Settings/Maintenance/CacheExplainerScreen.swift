import SwiftUI
import PhoebusCore

/// Apollo's cache explainer, reached from the Clear Browser Cache row: the user
/// cleared Apollo's cache and iOS still reports the app as large, because
/// WKWebView's website data counts against the app without being Apollo's to
/// delete.
public struct CacheExplainerScreen: View {
    @State private var entries: [CacheExplainer.Entry] = []
    @State private var isMeasuring = true

    public init() {}

    public var body: some View {
        List {
            Section {
                Text(CacheExplainer.introduction)
                Text(CacheExplainer.instructions)
            }
            .apolloCardRowFill()
            Section {
                if isMeasuring {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Measuring\u{2026}").foregroundStyle(.secondary)
                    }
                } else if entries.isEmpty {
                    Text("Couldn\u{2019}t read the app folder.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        HStack {
                            Text(entry.name)
                            Spacer()
                            Text(entry.formattedSize)
                                .foregroundStyle(.secondary)
                                // Monospaced digits so the sizes form a
                                // column rather than jitter per row.
                                .monospacedDigit()
                        }
                    }
                }
            } header: {
                Text(CacheExplainer.listingIntroduction)
                    // The listing intro is body copy, not an uppercase section header.
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }
            .apolloCardRowFill()
        }
        .apolloSettingsListAppearance()
        .navigationTitle(CacheExplainer.title)
        .navigationBarTitleDisplayModeIfAvailable()
        .accessibilityIdentifier("cacheExplainer.screen")
        .task {
            // Measured off the main actor: walking the container is
            // disk-bound and would otherwise stall presentation.
            let measured = await Task.detached(priority: .utility) {
                CacheExplainer.folderListing()
            }.value
            entries = measured
            isMeasuring = false
        }
    }
}
