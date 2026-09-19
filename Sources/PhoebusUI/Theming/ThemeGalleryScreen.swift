import SwiftUI
import PhoebusCore

/// Reborn's 50-theme gallery, compiled from its portable schema-v3 JSON through
/// the ported `ThemeCompiler`.
public struct ThemeGalleryScreen: View {
    /// Called with the chosen theme's slug once the user picks one.
    let onSelect: (GalleryTheme) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var previewMode: ThemeMode = ThemeStore.load().isDark ? .dark : .light

    public init(onSelect: @escaping (GalleryTheme) -> Void) {
        self.onSelect = onSelect
    }

    private var filtered: [GalleryTheme] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return ThemeGallery.all }
        // Reuses the settings-search normaliser so "catppuccin mocha"
        // and "Catppuccin Mocha" behave the same, rather than growing a
        // second, subtly different matching rule.
        let normalized = SettingsSearch.normalized(query)
        return ThemeGallery.all.filter {
            SettingsSearch.normalized($0.name).contains(normalized)
                || $0.slug.contains(normalized.replacingOccurrences(of: " ", with: "-"))
        }
    }

    public var body: some View {
        ScrollView {
            // Two columns: a gallery card has to show enough of a theme
            // to be worth browsing, and one column would make picking
            // among 50 a very long scroll.
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(filtered) { theme in
                    Button {
                        onSelect(theme)
                        dismiss()
                    } label: {
                        ThemeGalleryCard(theme: theme, mode: previewMode)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("themeGallery.\(theme.slug)")
                }
            }
            .padding(12)

            if filtered.isEmpty {
                ContentUnavailableViewIfAvailable(
                    title: "No Themes",
                    message: "No gallery themes match your search.",
                    systemImage: "paintpalette"
                )
                .padding(.top, 40)
            }
        }
        .background(Color(.systemGroupedBackground))
        // Filters the already-loaded gallery; bottom bar on glass.
        .apolloGlassSearchField(text: $searchText, prompt: "Search Themes")
        .navigationTitle("Theme Gallery")
        .navigationBarTitleDisplayModeIfAvailable()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // Every gallery theme ships BOTH modes, so the grid can
                // preview either without compiling anything extra.
                ApolloSettingsPicker("Preview", selection: $previewMode,
                                 options: [ThemeMode.light, ThemeMode.dark],
                                 display: { value in
                                     switch value {
                                     case ThemeMode.light: return "Light"
                                     case ThemeMode.dark: return "Dark"
                                     default: return "\(value)"
                                     }
                                 })
                .pickerStyle(.segmented)
                .frame(width: 130)
                .accessibilityIdentifier("themeGallery.modePicker")
            }
        }
    }
}

/// A single gallery card: a miniature of the app painted in the
/// theme's own compiled tokens.
///
/// Drawn from the compiled tokens rather than the raw input colours on
/// purpose - the point of a preview is to show what the theme will
/// actually look like, and half of what you see (separators, fills,
/// secondary text, selection) only exists after compilation.
struct ThemeGalleryCard: View {
    let theme: GalleryTheme
    let mode: ThemeMode

    private var compiled: CompiledTheme {
        ThemeGallery.compiled(slug: theme.slug) ?? theme.compiled()
    }

    private func color(_ token: ThemeToken) -> Color {
        Color(hex: compiled.hex(token, mode: mode))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Bar
            HStack(spacing: 4) {
                Circle().fill(color(.accent)).frame(width: 7, height: 7)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color(.label))
                    .frame(width: 40, height: 5)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(color(.barBackground))

            VStack(alignment: .leading, spacing: 6) {
                // A "post" card
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color(.label)).frame(height: 5)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color(.secondaryLabel)).frame(width: 70, height: 4)
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color(.accent)).frame(width: 16, height: 6)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color(.fill)).frame(width: 22, height: 6)
                    }
                }
                .padding(6)
                .background(color(.secondaryBackground), in: RoundedRectangle(cornerRadius: 5))

                Rectangle().fill(color(.separator)).frame(height: 1)

                // A "selected" row, which is the only place the
                // selection token shows up.
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color(.link)).frame(width: 34, height: 4)
                    Spacer()
                }
                .padding(5)
                .background(color(.selection), in: RoundedRectangle(cornerRadius: 4))

                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color(.tertiaryLabel)).frame(width: 46, height: 4)
                    Spacer()
                }
                .padding(.horizontal, 5)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color(.background))
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(color(.opaqueSeparator), lineWidth: 1)
        )
        .overlay(alignment: .bottom) {
            Text(theme.name)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
        }
        .frame(height: 132)
    }
}
