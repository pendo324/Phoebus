import Foundation
// No CoreGraphics: this is pure Double arithmetic so it builds on
// Linux, where the smoke tests run. The view layer converts to
// CGFloat at the call site.

/// The shared identity-header layout: banner, centred avatar, name,
/// subtitle. Everything stacks on the centre line with the avatar
/// straddling the banner's bottom edge. Profile and subreddit headers share
/// it.
///
/// A pure function in PhoebusCore so the arithmetic is testable on the host.
public enum IdentityHeaderLayout {
    /// The profile banner height. The subreddit header uses its own shorter
    /// 104pt, since its icon/name need less vertical room than a profile's
    /// avatar/bio showcase.
    public static let profileBannerHeight: Double = 150

    /// The subreddit banner height. The banner image's own aspect ratio may clip it.
    public static let subredditBannerHeight: Double = 104

    /// Avatar diameter, 96pt.
    public static let avatarDiameter: Double = 96

    /// How far the avatar hangs below the banner's bottom edge.
    public static let avatarOverlap: Double = 48

    /// Side inset.
    public static let sideInset: Double = 24

    /// Bottom padding.
    public static let bottomPadding: Double = 14

    /// Body column max width: centred bio/about text gets unreadably long
    /// lines on iPad/landscape without a cap.
    public static let bodyMaxWidth: Double = 480

    /// Name font: 28pt bold, scaled against Title1.
    public static let nameFontSize: Double = 28

    /// Subname font: 15pt medium, scaled against Subheadline.
    public static let subnameFontSize: Double = 15

    /// The avatar's top edge for a given banner height.
    ///
    /// The avatar overlaps the banner's bottom edge; with a short or absent
    /// banner it bottoms out at a 14pt top pad so it can't leave the top of the
    /// view.
    public static func avatarTop(bannerHeight: Double) -> Double {
        max(14, bannerHeight - avatarOverlap)
    }

    /// The centred body column's width.
    public static func bodyWidth(totalWidth: Double) -> Double {
        min(bodyMaxWidth, max(120, totalWidth - sideInset * 2))
    }

    /// The centred body column's leading edge.
    public static func bodyX(totalWidth: Double) -> Double {
        ((totalWidth - bodyWidth(totalWidth: totalWidth)) / 2).rounded(.down)
    }

    /// The avatar's leading edge, centred.
    public static func avatarX(totalWidth: Double) -> Double {
        ((totalWidth - avatarDiameter) / 2).rounded(.down)
    }

    /// Where the name sits: 8pt below the avatar.
    public static func nameTop(bannerHeight: Double) -> Double {
        avatarTop(bannerHeight: bannerHeight) + avatarDiameter + 8
    }
}
