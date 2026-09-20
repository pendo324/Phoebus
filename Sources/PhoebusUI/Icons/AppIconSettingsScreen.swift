import SwiftUI
import PhoebusCore
#if canImport(UIKit)
import UIKit
#endif

/// Apollo's App Icon picker + Community Icon Pack screen: the full 155-icon
/// catalog (`AppIconOption.all`, matching `Info.plist`) in a searchable grid.
///
/// Reborn's categorized, attributed "Liquid Glass" grid (85 icons, per-icon
/// designer attribution, 4 groups; `LiquidGlassIconOption`) sits above the flat
/// grid.

public struct AppIconSettingsScreen: View {
    /// Shared with the pushed pack screens, so a pick there checks itself at once.
    @ObservedObject private var iconSelection = AppIconSelection.shared
    private var selectedLiquidGlassID: String? {
        get { iconSelection.liquidGlassID }
        nonmutating set { iconSelection.liquidGlassID = newValue }
    }
    @State private var errorMessage: String?
    @State private var query = ""
    @Setting(LiquidGlassIconAppearanceStore.storage) private var appearance

    public init() {}

    private var filteredOptions: [AppIconOption] {
        guard !query.isEmpty else { return AppIconOption.all }
        return AppIconOption.all.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
    }

    /// The phone's current appearance, for picking a preview variant.
    @Environment(\.colorScheme) private var colorScheme

    private var previewVariant: String {
        appearance.previewVariant(systemIsDark: colorScheme == .dark)
    }

    /// The Daily Spotlight lineup, computed as Reborn does (see
    /// `LiquidGlassDailySpotlight`). Excludes the active icon.
    private var spotlightIcons: [LiquidGlassIconOption] {
        let ids = LiquidGlassDailySpotlight.icons(
            forDay: LiquidGlassDailySpotlight.dayIdentifier(),
            excluding: selectedLiquidGlassID.map { [$0] } ?? [])
        return ids.compactMap { id in
            LiquidGlassIconOption.all.first { $0.id == id }
        }
    }

    public var body: some View {
        ScrollView {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.caption).padding()
            }

            if query.isEmpty {
                spotlightSection
                packsSection(title: "Liquid Glass Icon Packs",
                             cards: LiquidGlassIconGroup.all.map { group in
                                 PackCardModel(
                                     id: group.id,
                                     title: group.title,
                                     iconCount: LiquidGlassIconOption.all
                                         .filter { $0.groupID == group.id }.count,
                                     coverIconIDs: coverIcons(for: group),
                                     isLiquidGlass: true)
                             })
                packsSection(title: "Standard Icon Packs",
                             cards: StandardIconPack.all.map { pack in
                                 PackCardModel(
                                     id: pack.id,
                                     title: pack.title,
                                     iconCount: pack.iconCount,
                                     coverIconIDs: pack.coverIconIDs,
                                     isLiquidGlass: false)
                             })
            } else {
                searchResults
            }
        }
        // Filters the loaded icon grid; bottom bar on glass.
        .apolloGlassSearchField(text: $query, prompt: "Search \(AppIconOption.all.count) icons")
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { appearanceMenu } }
    }

    /// Reborn puts this in the nav bar as a menu-backed bar button titled "<Mode> v",
    /// with a `UIMenu` titled "Icon Appearance" whose selected row is checked.
    private var appearanceMenu: some View {
        Menu {
            // `.inline`: this Picker is the menu's content, so the three modes render as
            // one checkmarked group.
            Picker("Icon Appearance", selection: $appearance.binding) {
                ForEach(LiquidGlassIconAppearance.allCases, id: \.self) { mode in
                    Label(mode.title, systemImage: mode.systemImageName)
                        .tag(mode)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Text("\(appearance.title) \u{25BE}")
        }
        .accessibilityLabel("Icon appearance")
        .accessibilityIdentifier("appIcon.appearanceMenu")
        .onChange(of: appearance) { _, mode in
            LiquidGlassIconAppearanceStore.save(mode)
            // Re-apply the active icon in the new appearance so the choice takes effect.
            if let active = selectedLiquidGlassID {
                Task { await applyLiquidGlass(id: active, mode: mode) }
            }
                }
    }

    /// The horizontal "Daily Spotlight" strip: 130pt tall, 128x112
    /// cards.
    @ViewBuilder
    private var spotlightSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daily Spotlight")
                .font(.title3.weight(.semibold))
                .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(spotlightIcons) { icon in
                        Button {
                            // Not from a back swipe that began on the card.
                            guard !PageSwipeController.isActive else { return }
                            Task { await selectLiquidGlass(icon) }
                        } label: {
                            spotlightCard(icon)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Double tap to change home screen app icon.")
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: 130)
        }
        .padding(.top, 8)
    }

    private func spotlightCard(_ icon: LiquidGlassIconOption) -> some View {
        VStack(spacing: 4) {
            LiquidGlassRenditionFan(
                iconID: icon.id,
                front: colorScheme == .dark ? "dark" : "default",
                back: colorScheme == .dark ? "default" : "dark",
                side: 64)
            Text(icon.displayName)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
            Text(icon.designer)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 128, height: 112)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(white: 0.11)))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selectedLiquidGlassID == icon.id ? Color.accentColor : .clear,
                              lineWidth: 2))
        .accessibilityLabel(
            "\(icon.displayName), by \(icon.designer)"
            + (selectedLiquidGlassID == icon.id ? ", selected" : ""))
    }

    /// A card is two-up on a phone; Reborn widens to three and four only on wide
    /// layouts.
    @ViewBuilder
    private func packsSection(title: String, cards: [PackCardModel]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.weight(.semibold))
                .padding(.horizontal)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)],
                      spacing: 12) {
                ForEach(cards) { card in
                    // A direct destination, not `NavigationLink(value:)` plus
                    // `.navigationDestination(for:)`: this screen is itself pushed onto the
                    // Settings stack, so a value-based destination is not the one nearest the
                    // stack's root and is ignored.
                    SettingsLink {
                        // A pushed screen is built once; this re-renders it
                        // when the selection changes.
                        AppIconSelectionObserver { packDetail(card) }
                    } label: {
                        LiquidGlassPackCard(
                            title: card.title,
                            iconCount: card.iconCount,
                            coverIconIDs: card.coverIconIDs,
                            isSelected: isSelected(card),
                            variant: previewVariant)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .padding(.top, 16)
    }

    private func isSelected(_ card: PackCardModel) -> Bool {
        if card.isLiquidGlass {
            guard let active = selectedLiquidGlassID else { return false }
            return LiquidGlassIconOption.all
                .contains { $0.id == active && $0.groupID == card.id }
        }
        return false
    }

    /// The pushed grid for one pack. Liquid Glass packs show the
    /// four-rendition cell (two fans, name, author); standard packs
    /// show Apollo's own bundled art.
    @ViewBuilder
    private func packDetail(_ pack: PackCardModel) -> some View {
        if pack.isLiquidGlass {
            liquidGlassPackDetail(pack)
        } else if let standard = StandardIconPack.all.first(where: { $0.id == pack.id }) {
            standardPackDetail(standard)
        }
    }

    private func liquidGlassPackDetail(_ pack: PackCardModel) -> some View {
        ScrollView {
            // Two-up. An `.adaptive(minimum: 100)` grid gives three columns on a wide
            // phone, past Reborn's wide-layout breakpoint.
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(LiquidGlassIconOption.all.filter { $0.groupID == pack.id }) { icon in
                    Button {
                        Task { await selectLiquidGlass(icon) }
                    } label: {
                        liquidGlassCell(icon)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Double tap to change home screen app icon.")
                }
            }
            .padding()
        }
        .navigationTitle(pack.title)
        .navigationBarTitleDisplayMode(.inline)
        // The appearance button stays in the bar on the pushed pack
        // screen too, beside the pack's own title.
        .toolbar { ToolbarItem(placement: .topBarTrailing) { appearanceMenu } }
    }

    /// Apollo's pack list: "<Pack> Icons" over 98pt rows of a 76pt icon 32pt in,
    /// the name 15pt after it with the designer under it (Community in larger
    /// type), and a check on the current icon.
    private func standardPackDetail(_ pack: StandardIconPack) -> some View {
        let large = pack.id == "community"
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text(pack.sectionTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.apolloSettingsSecondary)
                    .padding(.leading, 32)
                    .padding(.top, 20)
                    .padding(.bottom, 4)
                ForEach(pack.icons) { option in
                    Button {
                        Task { await select(option) }
                    } label: {
                        HStack(spacing: 15) {
                            IconPreview(option: option, side: 76)
                            VStack(alignment: .leading, spacing: large ? 3 : 2) {
                                Text(option.displayName)
                                    .font(.system(size: large ? 17 : 13, weight: large ? .regular : .medium))
                                    .foregroundStyle(Color.primary)
                                if let artist = option.artist {
                                    Text(artist)
                                        .font(.system(size: large ? 15 : 12))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 8)
                            if selectedLiquidGlassID == nil, iconSelection.standardID == option.id {
                                Image(systemName: "checkmark").foregroundStyle(Color.apolloAccent)
                            }
                        }
                        .frame(height: 98)
                        .padding(.leading, 32)
                        .padding(.trailing, 16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.apolloSeparator(colorScheme: colorScheme))
                            .frame(height: 1.0 / 3.0)
                            .padding(.leading, 123)
                    }
                    .accessibilityHint("Double tap to change home screen app icon.")
                }
            }
        }
        .apolloStockSurface()
        .navigationTitle(pack.screenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { appearanceMenu } }
    }

    private func liquidGlassCell(_ icon: LiquidGlassIconOption) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                LiquidGlassRenditionFan(
                    iconID: icon.id,
                    front: colorScheme == .dark ? "dark" : "default",
                    back: colorScheme == .dark ? "default" : "dark",
                    side: 46)
                LiquidGlassRenditionFan(
                    iconID: icon.id,
                    front: colorScheme == .dark ? "clear-dark" : "clear-light",
                    back: colorScheme == .dark ? "clear-light" : "clear-dark",
                    side: 46)
            }
            Text(icon.displayName)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
            Text(icon.designer)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(white: 0.11)))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selectedLiquidGlassID == icon.id ? Color.accentColor : .clear,
                              lineWidth: 2))
        .overlay(alignment: .topTrailing) {
            if selectedLiquidGlassID == icon.id {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.white, Color.accentColor)
                    .font(.system(size: 18))
                    .padding(6)
            }
        }
    }

    private func standardCell(_ option: AppIconOption) -> some View {
        VStack(spacing: 4) {
            IconPreview(option: option)
                .overlay(alignment: .topTrailing) {
                    if selectedLiquidGlassID == nil, iconSelection.standardID == option.id {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.white, .tint)
                            .background(Circle().fill(.white))
                            .padding(2)
                    }
                }
            Text(option.displayName)
                .font(.caption2)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    /// Search spans both catalogs, since the field's prompt promises a count across
    /// everything.
    @ViewBuilder
    private var searchResults: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
            ForEach(LiquidGlassIconOption.all.filter {
                $0.displayName.localizedCaseInsensitiveContains(query)
            }) { icon in
                Button {
                    Task { await selectLiquidGlass(icon) }
                } label: {
                    liquidGlassCell(icon)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Double tap to change home screen app icon.")
            }
            ForEach(filteredOptions) { option in
                Button {
                    Task { await select(option) }
                } label: {
                    standardCell(option)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Double tap to change home screen app icon.")
            }
        }
        .padding()
    }

    /// A group's cover icons, resolved against its own membership and capped to
    /// three, falling back to its first three rows so an unregistered ID never
    /// renders blank.
    private func coverIcons(for group: LiquidGlassIconGroup) -> [String] {
        let members = LiquidGlassIconOption.all.filter { $0.groupID == group.id }
        let resolved = group.coverIconIDs.filter { want in
            members.contains { $0.id == want }
        }
        if resolved.isEmpty { return members.prefix(3).map(\.id) }
        return Array(resolved.prefix(3))
    }

    private func selectLiquidGlass(_ icon: LiquidGlassIconOption) async {
        await applyLiquidGlass(id: icon.id, mode: appearance)
    }

    /// Applies a Liquid Glass icon in a given appearance. The appearance is part of
    /// the alternate icon's name (`LGAlternateIconNameForMode`), so changing either
    /// one goes through here.
    private func applyLiquidGlass(id: String, mode: LiquidGlassIconAppearance) async {
        #if canImport(UIKit)
        guard UIApplication.shared.supportsAlternateIcons else {
            errorMessage = "Alternate icons aren't supported on this device."
            return
        }
        do {
            try await Self.setAlternateIcon(
                named: "LGIcon-" + mode.alternateIconName(for: id))
            selectedLiquidGlassID = id
            LiquidGlassActiveIconStore.save(id)
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't switch icons: \(error.localizedDescription)"
        }
        #endif
    }

    private func select(_ option: AppIconOption) async {
        #if canImport(UIKit)
        guard UIApplication.shared.supportsAlternateIcons else {
            errorMessage = "Alternate icons aren't supported on this device."
            return
        }
        do {
            try await Self.setAlternateIcon(named: option.alternateIconName)
            AppIconStore.save(option)
            iconSelection.standardID = option.id
            // A standard icon replaces the Liquid Glass one.
            selectedLiquidGlassID = nil
            LiquidGlassActiveIconStore.save(nil)
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't switch icons: \(error.localizedDescription)"
        }
        #endif
    }

    #if canImport(UIKit)
    /// Sets the alternate icon without UIKit's confirmation alert, as Reborn does.
    ///
    /// UIKit's public setter routes through `LSIconAlertManager`; when that cannot
    /// mint an alert token (`NSPOSIXErrorDomain` 35) the whole change fails for
    /// every icon. The private setter skips the alert, with the public call kept as
    /// a fallback.
    private static func setAlternateIcon(named name: String?) async throws {
        let application = UIApplication.shared
        let selector = NSSelectorFromString("_setAlternateIconName:completionHandler:")
        guard application.responds(to: selector) else {
            try await application.setAlternateIconName(name)
            return
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            typealias QuietSetter = @convention(c) (
                AnyObject, Selector, NSString?, @escaping (NSError?) -> Void) -> Void
            let implementation = application.method(for: selector)
            let setter = unsafeBitCast(implementation, to: QuietSetter.self)
            setter(application, selector, name as NSString?) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
    #endif
}

/// One pack card's data, and the value a tap pushes.
/// The current icon, one copy for the picker and every pack screen it pushes.
@MainActor
final class AppIconSelection: ObservableObject {
    static let shared = AppIconSelection()
    @Published var liquidGlassID: String? = LiquidGlassActiveIconStore.load()
    @Published var standardID: String = AppIconStore.load().id
}

private struct AppIconSelectionObserver<Content: View>: View {
    @ObservedObject private var selection = AppIconSelection.shared
    @ViewBuilder let content: () -> Content

    var body: some View { content() }
}

struct PackCardModel: Identifiable, Hashable {
    let id: String
    let title: String
    let iconCount: Int
    let coverIconIDs: [String]
    /// Liquid Glass packs draw the community art and the four-rendition
    /// cell; standard packs draw Apollo's own bundled icons.
    let isLiquidGlass: Bool
}

/// A small preview swatch for an icon option.
private struct IconPreview: View {
    let option: AppIconOption
    var side: CGFloat = 56

    var body: some View {
        Group {
            if let image = Self.preview(for: option) {
                #if canImport(UIKit)
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                #else
                placeholder
                #endif
            } else {
                placeholder
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side * 0.225, style: .continuous))
    }

    /// Apollo's own icon art, loaded straight from the bundle root, which is where
    /// alternate icons must live.
    #if canImport(UIKit)
    private static func preview(for option: AppIconOption) -> UIImage? {
        // The default icon is stored under its slug, not "original".
        let slug = option.id == "original" ? "Original" : option.id
        for scale in ["@3x", "@2x"] {
            if let path = Bundle.main.path(forResource: "AppIcon-\(slug)60x60\(scale)",
                                           ofType: "png"),
               let image = UIImage(contentsOfFile: path) {
                return image
            }
        }
        return nil
    }
    #else
    private static func preview(for option: AppIconOption) -> PlatformPreviewImage? { nil }
    #endif

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(gradient)
    }

    /// Only reached when an icon has no bundled art.
    private var gradient: LinearGradient {
        var hasher = Hasher()
        hasher.combine(option.id)
        let hash = abs(hasher.finalize())
        let hue1 = Double(hash % 360) / 360.0
        let hue2 = Double((hash / 360) % 360) / 360.0
        let color1 = Color(hue: hue1, saturation: 0.65, brightness: 0.85)
        let color2 = Color(hue: hue2, saturation: 0.75, brightness: 0.65)
        return LinearGradient(colors: [color1, color2], startPoint: .top, endPoint: .bottom)
    }
}

#if !canImport(UIKit)
private struct PlatformPreviewImage {}
#endif
