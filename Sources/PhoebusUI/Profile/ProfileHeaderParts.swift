import SwiftUI
import PhoebusCore

/// One of the profile's menu rows.
enum ProfileMenuRow: Hashable {
    case tab(UserProfileScreen.ProfileTab)
    case hiddenAndDeleted
    case moderatorZone

    var title: String {
        switch self {
        case .tab(let tab): return tab.rawValue
        case .hiddenAndDeleted: return "Hidden & Deleted"
        case .moderatorZone: return "Moderator Zone"
        }
    }

    /// Apollo's own row glyphs, at their own size.
    var icon: String? {
        switch self {
        case .tab(.posts): return "option-posts"
        case .tab(.comments): return "option-comments"
        case .tab(.saved): return "option-save"
        case .tab(.friends): return "option-friends"
        case .tab(.upvoted): return "option-upvote"
        case .tab(.downvoted): return "option-downvote"
        case .tab(.hidden): return "option-hide"
        case .tab(.trophies): return "option-trophy"
        case .moderatorZone: return "option-moderator"
        default: return nil
        }
    }

    var systemImage: String {
        switch self {
        case .tab(let tab): return tab.systemImage
        case .hiddenAndDeleted: return "eye.slash"
        case .moderatorZone: return "shield"
        }
    }
}

extension View {
    /// A row of the profile's list drawn edge to edge with no system
    /// chrome: the header and the menu rows draw their own.
    func profileFullBleedRow() -> some View {
        listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

/// Apollo's profile menu row (393pt screen): 44pt tall, glyph centred at x 45 in
/// the accent (Moderator Zone in green), title at x 77 in 17pt, chevron 31pt from
/// the right, rule from x 75 to 15pt short of the right edge.
struct ProfileMenuRowView: View {
    let row: ProfileMenuRow
    let separator: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.apolloTheme) private var apolloTheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Group {
                    if let icon = row.icon {
                        StockPNG.image(icon)
                    } else {
                        Image(systemName: row.systemImage).font(.system(size: 20))
                    }
                }
                .foregroundStyle(row == .moderatorZone
                                 ? Color(red: 103 / 255, green: 206 / 255, blue: 103 / 255)
                                 : Color.apolloAccent)
                .frame(width: 30)
                .padding(.leading, 30)
                Text(row.title)
                    .font(.system(size: 17))
                    .foregroundStyle(Color.apolloPrimaryText(colorScheme: colorScheme, themeColors: apolloTheme))
                    .lineLimit(1)
                    .padding(.leading, 17)
                Spacer(minLength: 8)
                ApolloSettingsChevron()
                    .padding(.trailing, 31)
            }
            .frame(height: 44.3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if separator {
                ApolloSettingsSeparator()
                    .padding(.leading, 75)
                    .padding(.trailing, 15)
            }
        }
        .accessibilityIdentifier("profile.row.\(row.title)")
    }
}

/// The "OVERVIEW" caption over the inline listing: 13pt grey caps at
/// x 16, a full-width rule under it.
struct ProfileOverviewCaption: View {
    var body: some View {
        Text("OVERVIEW")
            .font(.system(size: 13))
            .foregroundStyle(Color.apolloSettingsSecondary)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .bottomLeading)
            .padding(.leading, 16)
            .padding(.bottom, 7)
            .padding(.top, 13)
            .overlay(alignment: .bottom) { ApolloSettingsSeparator() }
    }
}

/// The bio: Body text, three lines with a "more" / "less" toggle when it
/// runs longer (`ApolloProfileAboutCollapsedLines`).
struct ProfileBio: View {
    let text: String
    let centered: Bool
    @State private var expanded = false
    @State private var truncates = false

    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: 0) {
            Text(text)
                .font(.body)
                .multilineTextAlignment(centered ? .center : .leading)
                .lineLimit(expanded ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    // The full text's height, to know whether three lines cut it.
                    Text(text).font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChangeIfAvailable(of: \.size.height) { full in
                            truncates = full > UIFont.preferredFont(forTextStyle: .body).lineHeight * 3 + 1
                        }
                )
            if truncates || expanded {
                Button(expanded ? "less" : "more") { expanded.toggle() }
                    .font(.footnote)
                    .foregroundStyle(Color.apolloAccent)
                    .frame(height: 22)
            }
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        .contentShape(Rectangle())
        .onTapGesture { if truncates || expanded { expanded.toggle() } }
    }
}

extension View {
    /// `onGeometryChange` is iOS 18 (back-deployed to 16 in the SDK, but
    /// guarded here as the rest of the package does).
    @ViewBuilder
    func onGeometryChangeIfAvailable(of value: @escaping @Sendable (CGRect) -> CGFloat,
                                     action: @escaping (CGFloat) -> Void) -> some View {
        if #available(iOS 18.0, *) {
            onGeometryChange(for: CGFloat.self) { value($0.frame(in: .local)) } action: { action($0) }
        } else {
            background(GeometryReader { proxy in
                Color.clear
                    .onAppear { action(value(proxy.frame(in: .local))) }
                    .onChange(of: value(proxy.frame(in: .local))) { _, new in action(new) }
            })
        }
    }
}

/// Reborn's Badge Book band: 44pt, a rosette and "Badge Book" in the accent,
/// earned trophies at 30pt 6pt apart, a chevron at the far edge. The whole band
/// opens the Badge Book.
struct ProfileBadgeBookBand: View {
    let trophies: [RedditTrophy]
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            GeometryReader { proxy in
                let available = proxy.size.width - 20 - 8 - 86 - 12 - 13 - 8
                let fit = max(0, Int((available + 6) / 36))
                let icons = trophies.filter { $0.iconURL != nil || BundledBadgeArt.catalog.trophyFile(iconURL: nil, title: $0.name) != nil }
                let overflow = icons.count > fit
                let shown = overflow ? max(0, fit - 1) : icons.count
                HStack(spacing: 0) {
                    Image(systemName: "rosette")
                        .font(.system(size: 17))
                        .frame(width: 20, height: 20)
                        .foregroundStyle(Color.apolloAccent)
                    Text("Badge Book")
                        .font(.subheadline)
                        .foregroundStyle(Color.apolloAccent)
                        .padding(.leading, 8)
                    HStack(spacing: 6) {
                        ForEach(Array(icons.prefix(shown))) { trophy in
                            BadgeArtImage(file: BundledBadgeArt.catalog.trophyFile(iconURL: trophy.iconURL, title: trophy.name),
                                          remoteURL: trophy.iconURL.flatMap(URL.init(string:)))
                                .frame(width: 30, height: 30)
                        }
                        if overflow {
                            Text("+\(icons.count - shown)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.leading, 12)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 13)
                }
                .frame(height: proxy.size.height)
            }
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(trophies.isEmpty ? "Badge Book" : "Badge Book, \(trophies.count) badges")
        .accessibilityIdentifier("profile.badgeBook")
    }
}

/// Reborn's three stat cards: Post Karma, Comment Karma, Reddit Age, each 66pt
/// tall with 18pt corners, 10pt apart: the value 18pt bold over an 11pt semibold
/// caption. A tap shows the exact count, or the join date.
struct ProfileStatCards: View {
    let user: RedditUser
    @State private var detail: (title: String, message: String)?

    var body: some View {
        HStack(spacing: 10) {
            card(Self.formatCount(user.linkKarma), "Post Karma") {
                detail = ("Post Karma", user.linkKarma.formatted())
            }
            card(Self.formatCount(user.commentKarma), "Comment Karma") {
                detail = ("Comment Karma", user.commentKarma.formatted())
            }
            card(Self.formatAge(user.created), "Reddit Age") {
                let joined = user.created.formatted(date: .long, time: .omitted)
                detail = ("Reddit Age", "Joined \(joined)")
            }
        }
        .alert(detail?.title ?? "", isPresented: Binding(get: { detail != nil }, set: { if !$0 { detail = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(detail?.message ?? "")
        }
    }

    private func card(_ value: String, _ caption: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.primary)
                    .minimumScaleFactor(0.7)
                    .frame(height: 22)
                Text(caption)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.75)
                    .frame(height: 14)
            }
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .frame(height: 66)
            .apolloGlassBackground(in: RoundedRectangle(cornerRadius: 18, style: .continuous),
                                   fallback: .thinMaterial, interactive: true)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(caption): \(value)")
    }

    /// 1.2k / 45k / 1.3M, as Reborn formats karma.
    static func formatCount(_ value: Int) -> String {
        let v = Double(value)
        if v >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000) }
        if v >= 100_000 { return String(format: "%.0fk", v / 1000) }
        if v >= 1000 { return String(format: "%.1fk", v / 1000) }
        return "\(value)"
    }

    /// "4y 2mo", "7mo", "New".
    static func formatAge(_ created: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: created, to: Date())
        let years = c.year ?? 0, months = c.month ?? 0
        if years >= 1 { return months > 0 ? "\(years)y \(months)mo" : "\(years)y" }
        if months >= 1 { return "\(months)mo" }
        return "New"
    }
}

/// Apollo's stock header (Profile Style "Native"): three bare columns,
/// a 20pt medium value over a two-line grey caption.
struct NativeProfileStats: View {
    let user: RedditUser

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            stat(Self.formatCount(user.commentKarma), "Comment\nKarma")
            stat(Self.formatCount(user.linkKarma), "Post\nKarma")
            stat(Self.formatAge(user.created), "Account\nAge")
        }
        .padding(.horizontal, 12)
        .padding(.top, 26)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
    }

    private func stat(_ value: String, _ caption: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(caption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// 948 / 4.2K / 607.5K / 1.3M.
    static func formatCount(_ value: Int) -> String {
        let v = Double(value)
        if abs(v) >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000) }
        if abs(v) >= 1000 { return String(format: "%.1fK", v / 1000) }
        return "\(value)"
    }

    /// "14y 6mo", "7mo", "8d".
    static func formatAge(_ created: Date, now: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: created, to: now)
        let years = c.year ?? 0, months = c.month ?? 0
        if years >= 1 { return months > 0 ? "\(years)y \(months)mo" : "\(years)y" }
        if months >= 1 { return "\(months)mo" }
        return "\(max(c.day ?? 0, 1))d"
    }
}

/// Reborn's Follow / Message pills on someone else's profile: a 42pt
/// Follow capsule at least 148pt wide and a 58pt envelope capsule, both
/// in the accent, 10pt apart.
struct ProfileActionButtons: View {
    let username: String
    let repository: RedditRepository
    let message: () -> Void
    @State private var following = false

    var body: some View {
        let onAccent = Color.white
        HStack(spacing: 10) {
            Button {
                let follow = !following
                following = follow
                Task {
                    if follow {
                        try? await repository.followUser(username: username)
                    } else {
                        try? await repository.unfollowUser(username: username)
                    }
                }
            } label: {
                Text(following ? "Following" : "Follow")
                    .font(.system(size: 16.5, weight: .semibold))
                    .foregroundStyle(onAccent)
                    .padding(.horizontal, 26)
                    .frame(minWidth: 148, minHeight: 42)
                    .background(Capsule().fill(Color.apolloAccent.opacity(0.92)))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.followButton")
            Button(action: message) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(onAccent)
                    .frame(width: 58, height: 42)
                    .background(Capsule().fill(Color.apolloAccent.opacity(0.92)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Message")
            .accessibilityIdentifier("profile.messageButton")
        }
    }
}

/// Apollo's Moderator Zone: the combined queue for every subreddit you
/// moderate, then each subreddit's own.
struct ModeratorZoneScreen: View {
    let repository: RedditRepository
    @State private var subreddits: [RedditSubreddit] = []

    var body: some View {
        List {
            Section {
                SettingsLink("All Moderated Subreddits") {
                    ModQueueScreen(subreddit: "mod", repository: repository)
                }
                .apolloSearchRow("All Moderated Subreddits", lastBeforeFooter: true)
            }
            if !subreddits.isEmpty {
                Section {
                    ForEach(subreddits) { subreddit in
                        SettingsLink("r/\(subreddit.displayName)") {
                            ModQueueScreen(subreddit: subreddit.displayName, repository: repository)
                        }
                        .apolloPlainSettingsRowInsets(rule: subreddit.id != subreddits.last?.id)
                    }
                } header: {
                    Text("Subreddits")
                        .apolloSectionHeader()
                }
            }
        }
        .apolloSettingsListAppearance()
        .navigationTitle("Moderator Zone")
        .navigationBarTitleDisplayModeIfAvailable()
        .apolloForwardSwipe()
        .task {
            if subreddits.isEmpty {
                subreddits = (try? await repository.fetchModeratedSubreddits()) ?? []
            }
        }
    }
}
