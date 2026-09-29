import SwiftUI
import PhoebusCore

/// Live preview for the Profile Layout settings screen.
///
/// Reborn's preview hosts the production profile header configured with a
/// local fixture, inside a 22pt continuous-corner card. This reproduces that
/// header from its layout constants: a rounded card, a real avatar image,
/// gradient-accent buttons, rounded stat cards and badge glyphs.
///
/// Key measurements:
/// - Header: banner 150, avatar 96 overlapping the banner by 48, 24pt
///   side inset, name 28pt bold 8pt below the avatar, subname 15pt
///   medium +1, body starts subname + 10, bottom padding 14.
/// - Follow/Message row 42pt tall (Follow >= 148 wide, Message >= 58,
///   10pt apart, 16pt below), social band +8, badge band +10, stat
///   cards +14, 66pt tall, 10pt apart, 15pt grouped margin, 18pt
///   corner, 18pt bold value over 11pt semibold caption, white 12%
///   rim + black shadow.
/// - "Social Links" caption (Caption1) 16pt tall, 5pt gap, 36pt pills
///   on tertiarySystemFill, 12/14 insets, 20pt icon, 8pt icon gap.
/// - Badge strip: 44pt strip, 20pt accent rosette, title 8pt after it
///   (Subheadline, accent), 30pt icons 6pt apart starting 12pt after
///   the title, 13pt tertiary chevron at the trailing edge.
/// - Banner: the page colour with three accent/white ellipses; in Immersive
///   mode the ambient view melts it down the whole card.
/// - Native layout: a username pill, then three bare stats (20pt
///   medium values, Subheadline captions "Comment\nKarma" /
///   "Post\nKarma" / "Account\nAge").
struct ProfileLayoutPreviewMock: View {
    let settings: ProfileLayoutSettings
    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color { Color.apolloAccent }
    private var immersive: Bool { settings.headerImmersive }

    // Avatar and overlap constants.
    private let avatarDiameter: CGFloat = 96
    private let avatarOverlap: CGFloat = 48
    private let sideInset: CGFloat = 24
    private let groupedMargin: CGFloat = 15
    /// Banner height: 0 when off, 104 Compact, 150 Immersive.
    private var bannerHeight: CGFloat {
        guard settings.showBanner else { return 0 }
        return immersive ? 150 : 104
    }

    var body: some View {
        Group {
            if settings.style == .native {
                nativeHeader
            } else {
                rebornHeader
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .animation(.easeInOut(duration: 0.25), value: settings)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Reborn header (Immersive / Compact)

    private var rebornHeader: some View {
        VStack(spacing: 0) {
            identity
            body_
        }
        .padding(.bottom, 14)
        // A background, never a ZStack sibling: the page `Color` in it is flexible,
        // and as a sibling it sizes the card to whatever height it is offered.
        // Pinned in the `safeAreaInset` the card grows to the whole screen, so
        // `pinningAvailable` goes false; unpinned it shrinks back and pinning
        // returns, looping forever with the UI frozen.
        .background(alignment: .top) { background }
    }

    /// Immersive: the banner art melted down the whole card (blurred,
    /// fading into the page colour). Compact: the banner as a plain
    /// strip over the page colour.
    @ViewBuilder private var background: some View {
        let page = colorScheme == .dark ? Color.black : Color.white
        if immersive && settings.showBanner {
            ZStack(alignment: .top) {
                page
                bannerArt
                    .frame(height: 420)
                    .blur(radius: 18)
                    .mask(LinearGradient(colors: [.black, .black.opacity(0.55), .clear],
                                         startPoint: .top, endPoint: .bottom))
                // The sharp banner on top of its own melt, so the ellipse shapes still read.
                bannerArt
                    .frame(height: bannerHeight)
                    .mask(LinearGradient(colors: [.black, .black, .clear],
                                         startPoint: .top, endPoint: .bottom))
            }
        } else {
            ZStack(alignment: .top) {
                page
                if settings.showBanner {
                    bannerArt.frame(height: bannerHeight).clipped()
                }
            }
        }
    }

    /// Banner art: page fill, then accent 0.82 ellipse (-70,-85,270,240), accent
    /// 0.45 ellipse (135,-60,260,215) and white 0.10 ellipse (70,42,250,135), on a
    /// 320x120 canvas stretched to fill.
    private var bannerArt: some View {
        GeometryReader { proxy in
            let sx = proxy.size.width / 320
            let sy = proxy.size.height / 120
            ZStack(alignment: .topLeading) {
                (colorScheme == .dark ? Color.black : Color.white)
                Ellipse().fill(accent.opacity(0.82))
                    .frame(width: 270 * sx, height: 240 * sy)
                    .offset(x: -70 * sx, y: -85 * sy)
                Ellipse().fill(accent.opacity(0.45))
                    .frame(width: 260 * sx, height: 215 * sy)
                    .offset(x: 135 * sx, y: -60 * sy)
                Ellipse().fill(Color.white.opacity(0.10))
                    .frame(width: 250 * sx, height: 135 * sy)
                    .offset(x: 70 * sx, y: 42 * sy)
            }
        }
        .clipped()
    }

    /// Avatar, name and the Follow/Message row.
    @ViewBuilder private var identity: some View {
        let avatarY = max(14, bannerHeight - avatarOverlap)
        if immersive {
            VStack(spacing: 0) {
                avatar.padding(.top, avatarY)
                Text("iamthatis")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .padding(.top, 8)
                    .padding(.horizontal, sideInset)
                if settings.showActions {
                    actions.padding(.top, 14)
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            // Compact: the avatar on the 15pt grouped margin, the name 12pt beside it
            // starting at the banner's bottom edge (20pt bold).
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    avatar
                    Text("iamthatis")
                        .font(.system(size: 20, weight: .bold))
                        .lineLimit(1)
                        .padding(.top, settings.showBanner ? avatarOverlap : 34)
                    Spacer(minLength: 0)
                }
                .padding(.top, avatarY)
                if settings.showActions {
                    actions.padding(.top, 14)
                }
            }
            .padding(.horizontal, groupedMargin)
        }
    }

    @ViewBuilder private var avatar: some View {
        let art = PreviewAvatarArt()
            .frame(width: avatarDiameter, height: avatarDiameter)
        switch settings.avatarStyle {
        case .square:
            // `MIN(18, diameter * 0.24)`.
            art.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        case .circle, .full:
            // Avatar style: Square -> rounded square; Full/Circle -> circle. Full
            // differs only for snoovatars, which the fixture does not have.
            art.clipShape(Circle())
        }
    }

    /// Follow pill + envelope pill, glass tinted with the accent (0.62).
    private var actions: some View {
        HStack(spacing: 10) {
            Text("Follow")
                .font(.system(size: 16.5, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 148, height: 42)
                .background(Capsule().fill(accent.opacity(0.62)))
                .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
            Image(systemName: "envelope.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 42)
                .background(Capsule().fill(accent.opacity(0.62)))
                .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
        }
        .frame(maxWidth: .infinity, alignment: immersive ? .center : .leading)
    }

    /// Bio, social links, badge strip, stat cards.
    private var body_: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The fixture bio is forced to one line in the preview (shrinks to 0.70).
            Text("I build Apollo for Reddit, an iOS Reddit client. :)")
                .font(.body)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: immersive ? .center : .leading)
                .padding(.top, settings.showActions ? 16 : 10)
            if settings.showSocialLinks {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Social Links")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(height: 16)
                    HStack(spacing: 8) {
                        socialPill(system: "m.circle.fill", tint: Color(hex: "6364FF"))
                        socialPill(system: "bird.fill", tint: Color(hex: "1D9BF0"))
                    }
                }
                .padding(.top, 8)
            }
            if settings.badgeBookEnabled {
                badgeStrip.padding(.top, 10)
            }
            if settings.showStatCards {
                HStack(spacing: 10) {
                    statCard("529k", "Post Karma")
                    statCard("607k", "Comment Karma")
                    statCard("15y 9mo", "Reddit Age")
                }
                .padding(.horizontal, groupedMargin - sideInset)
                .padding(.top, 14)
            }
        }
        .padding(.horizontal, immersive ? sideInset : groupedMargin)
    }

    private func socialPill(system: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: system)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(tint))
            Text("@ChristianSelig")
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .frame(height: 36)
        .background(Capsule().fill(Color(.tertiarySystemFill)))
    }

    private var badgeStrip: some View {
        HStack(spacing: 0) {
            Image(systemName: "rosette")
                .font(.system(size: 17))
                .foregroundStyle(accent)
                .frame(width: 20, height: 20)
            Text("Badge Book")
                .font(.subheadline)
                .foregroundStyle(accent)
                .padding(.leading, 8)
            HStack(spacing: 6) {
                ForEach(Array(zip(["trophy.fill", "star.fill", "flame.fill"],
                                  [Color(hex: "3D8A5A"), Color(hex: "D9534F"), Color(hex: "F0AD4E")])),
                        id: \.0) { glyph, tint in
                    Image(systemName: glyph)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(tint))
                        .overlay(Circle().stroke(Color(hex: "E8B53A"), lineWidth: 2))
                }
            }
            .padding(.leading, 12)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(height: 44)
    }

    private func statCard(_ value: String, _ caption: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: 22)
            Text(caption)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(height: 14)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .frame(height: 66)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.thinMaterial)
                .shadow(color: .black.opacity(0.28), radius: 7, y: 3)
        )
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    // MARK: - Native

    /// Apollo's stock header: the username (17pt semibold) 16pt from the top in
    /// a 44pt glass pill, then 34pt lower three bare stats: 20pt medium values
    /// over Subheadline two-line captions, columns 12pt in from each side.
    private var nativeHeader: some View {
        VStack(spacing: 0) {
            Text("iamthatis")
                .font(.system(size: 17, weight: .semibold))
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(Capsule().fill(Color(.tertiarySystemFill)))
                .padding(.top, 16)
            HStack(alignment: .top, spacing: 0) {
                nativeStat("607.5K", "Comment\nKarma")
                nativeStat("529.0K", "Post\nKarma")
                nativeStat("15y 8mo", "Account\nAge")
            }
            .padding(.horizontal, 12)
            .padding(.top, 34)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .background(colorScheme == .dark ? Color.black : Color.white)
    }

    private func nativeStat(_ value: String, _ caption: String) -> some View {
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
    }

    private var accessibilityText: String {
        if settings.style == .native {
            return "Native profile preview for u slash iamthatis. Comment Karma 607.5 thousand. Post Karma 529 thousand. Account Age 15 years 8 months."
        }
        func shown(_ b: Bool) -> String { b ? "shown" : "hidden" }
        let avatar = settings.avatarStyle == .square ? "square" : (settings.avatarStyle == .circle ? "circle" : "full")
        return "\(immersive ? "Immersive" : "Compact") profile preview for u slash iamthatis. \(avatar) avatar. Banner \(shown(settings.showBanner)). Stat cards \(shown(settings.showStatCards)). Social links \(shown(settings.showSocialLinks)). Badge Book \(shown(settings.badgeBookEnabled)). Follow and Message \(shown(settings.showActions))."
    }
}

/// The fixture avatar: Reborn reuses the widget's bundled Apollo avatar so
/// the preview needs no network or cached Reddit profile image. Falls back
/// to a person glyph.
private struct PreviewAvatarArt: View {
    var body: some View {
        #if canImport(UIKit)
        if let url = Bundle.module.url(forResource: "apollo-avatar@3x", withExtension: "png",
                                       subdirectory: "StockIcons"),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            placeholder
        }
        #else
        placeholder
        #endif
    }

    private var placeholder: some View {
        Color(.tertiarySystemFill)
            .overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))
    }
}
