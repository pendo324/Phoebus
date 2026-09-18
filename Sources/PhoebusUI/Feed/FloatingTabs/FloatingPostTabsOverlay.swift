import SwiftUI
import PhoebusCore

/// Reborn's "Floating Post Tabs" overlay (see `FloatingPostTabsSettings`):
/// up to 5 posts stay open as small draggable circular bubbles
/// (chat-heads style) that jump back into the post on tap.
///
/// - Tapping a bubble presents `PostDetailScreen` in a `fullScreenCover`.
///   Dropping one on the X-shaped drop zone removes it.
/// - **Hold to Preview**: a `LongPressGesture`, combined with the drag so
///   hold-then-drag still works, shows an inline preview card of the
///   post's title/subreddit while held, and opens the post on release if
///   the press ran long enough without turning into a drag.
/// - **Magnetic Stacking**, as Reborn's piles: releasing a bubble
///   within 70pt of another clicks them into a pile (the target swells
///   while hovered); dragging any member moves the whole pile, the ones
///   behind trailing; tapping a pile fans it apart, and the members not
///   dragged away regather after 6 s; dropping a pile on the X closes all
///   of it; turning the setting off fans every pile out.
public struct FloatingPostTabsOverlay: View {
    @ObservedObject var manager: FloatingPostTabsManager
    let repository: RedditRepository
    @Setting(FloatingPostTabsSettingsStore.storage) private var settings
    @State private var positions: [String: CGPoint] = [:]
    @State private var dragTranslations: [String: CGSize] = [:]
    @State private var previewingPostID: String?
    @State private var presentedPost: RedditPost?
    @State private var showingDropZone = false
    @State private var hoveringDropZone = false
    @State private var piles = FloatingTabPiles()
    /// The bubble a drag would join, swelling as the "will attach" hint.
    @State private var magnetTarget: String?
    /// The last fan's members, waiting to spring back into a pile.
    @State private var regatherGroup: [String] = []
    @State private var regatherAnchor: CGPoint?
    @State private var regatherGeneration = 0

    private static let bubbleSize: CGFloat = 56
    // Reborn's tunables.
    private static let snapRadius: CGFloat = 70
    private static let fanSpacing: CGFloat = 80
    private static let stackPeek: CGFloat = 13
    private static let regatherDelay: Duration = .seconds(6)
    private static let dropZoneSize: CGFloat = 64

    public init(manager: FloatingPostTabsManager, repository: RedditRepository) {
        self.manager = manager
        self.repository = repository
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(Array(manager.keptPosts.enumerated()), id: \.element.id) { index, post in
                    bubble(for: post, index: index, containerSize: proxy.size)
                }
                if showingDropZone {
                    dropZone(containerSize: proxy.size)
                }
            }
        }
        .allowsHitTesting(!manager.keptPosts.isEmpty)
        .onChange(of: manager.keptPosts.map(\.id)) { _, ids in
            piles.prune(keeping: Set(ids))
        }
        .onChange(of: settings.magneticStacking) { _, on in
            guard !on else { return }
            for (stack, _) in piles.piles { fanOut(stack, regathers: false) }
        }
        .fullScreenCover(item: $presentedPost) { post in
            NavigationStack {
                PostDetailScreen(post: post, repository: repository)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { presentedPost = nil }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private func bubble(for post: RedditPost, index: Int, containerSize: CGSize) -> some View {
        let order = piles.order(of: post.id)
        let anchor = restingPosition(of: post.id, containerSize: containerSize)
        let restingPosition = CGPoint(x: anchor.x, y: anchor.y + CGFloat(order) * Self.stackPeek)
        let translation = dragTranslations[post.id] ?? .zero
        let isPreviewing = previewingPostID == post.id
        let scale = (order > 0 ? max(0.8, 1 - 0.07 * CGFloat(order)) : 1) * (magnetTarget == post.id ? 1.15 : 1)

        ZStack {
            Circle()
                .fill(.thinMaterial)
                .overlay(Circle().stroke(Color.apolloAccent, lineWidth: 2))
                .frame(width: Self.bubbleSize, height: Self.bubbleSize)
            if let thumbnailURL = post.thumbnail.flatMap({ URL(string: $0) }), post.thumbnail?.hasPrefix("http") == true {
                CachedAsyncImage(url: thumbnailURL)
                    .frame(width: Self.bubbleSize - 8, height: Self.bubbleSize - 8)
                    .clipShape(Circle())
            } else {
                Text(String(post.subreddit.prefix(1)).uppercased())
                    .font(.headline.bold())
                    .foregroundStyle(.primary)
            }
        }
        .overlay(alignment: .top) {
            if isPreviewing {
                previewCard(for: post)
                    .offset(y: -84)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
            }
        }
        .scaleEffect(scale)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: scale)
        .position(x: restingPosition.x + translation.width, y: restingPosition.y + translation.height)
        .accessibilityIdentifier("floatingPostTabs.bubble.\(post.id)")
        .gesture(dragGesture(for: post, containerSize: containerSize))
        .modifier(HoldToPreviewModifier(
            enabled: settings.holdToPreview,
            onHold: { previewingPostID = post.id },
            onRelease: { openedByHold in
                previewingPostID = nil
                if openedByHold { presentedPost = post }
            }
        ))
        .onTapGesture {
            guard previewingPostID == nil else { return }
            // A pile's tap fans it apart: that is the pull-apart gesture.
            if let stack = piles.stackID(of: post.id) {
                fanOut(stack, containerSize: containerSize)
            } else {
                presentedPost = post
            }
        }
        // Members behind the front trail the drag with a springier lag.
        .animation(.spring(response: 0.3 + 0.07 * Double(order), dampingFraction: 0.7), value: translation)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: restingPosition)
        .zIndex(previewingPostID == post.id ? 100 : Double(index) - Double(order) * 10)
    }

    private func previewCard(for post: RedditPost) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("r/\(SubredditCapitalization.display(post.subreddit))")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            Text(post.title)
                .font(.caption)
                .lineLimit(3)
                .foregroundStyle(.primary)
        }
        .padding(8)
        .frame(width: 180, alignment: .leading)
        // The shadow is a FALLBACK: real glass shades itself, and
        // drawing both rings the edge.
        .apolloGlassBackground(
            in: RoundedRectangle(cornerRadius: 10),
            fallback: .regularMaterial,
            fallbackShadow: (.black.opacity(0.33), 4, 0)
        )
    }

    /// Bubble repositioning, drop-to-close and magnetic stacking. Hold to
    /// Preview is handled separately by `HoldToPreviewModifier`, since
    /// `.onLongPressGesture` composes with a plain `DragGesture` more
    /// predictably than two custom recognizers on one view.
    private func dragGesture(for post: RedditPost, containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                previewingPostID = nil
                showingDropZone = true
                // The whole pile moves with any member.
                let group = piles.members(of: post.id)
                for id in group { dragTranslations[id] = value.translation }
                // Dragged out of a fan: that one stays out.
                regatherGroup.removeAll { group.contains($0) }
                let anchor = restingPosition(of: post.id, containerSize: containerSize)
                let currentPoint = CGPoint(x: anchor.x + value.translation.width, y: anchor.y + value.translation.height)
                hoveringDropZone = distance(currentPoint, dropZonePosition(containerSize: containerSize)) < Self.dropZoneSize
                magnetTarget = settings.magneticStacking && !hoveringDropZone
                    ? nearestTarget(to: currentPoint, excluding: group, containerSize: containerSize) : nil
            }
            .onEnded { value in
                showingDropZone = false
                let group = piles.members(of: post.id)
                let anchor = restingPosition(of: post.id, containerSize: containerSize)
                let finalPoint = CGPoint(x: anchor.x + value.translation.width, y: anchor.y + value.translation.height)
                let target = magnetTarget
                magnetTarget = nil
                defer { for id in group { dragTranslations[id] = nil } }

                if distance(finalPoint, dropZonePosition(containerSize: containerSize)) < Self.dropZoneSize {
                    // Dropped on the X: the whole pile closes.
                    for id in group {
                        if let kept = manager.keptPosts.first(where: { $0.id == id }) { manager.remove(post: kept) }
                        positions[id] = nil
                    }
                    piles.prune(keeping: Set(manager.keptPosts.map(\.id)))
                    hoveringDropZone = false
                    return
                }

                if settings.magneticStacking, let target {
                    // Click together: the group goes to the front of the target's pile.
                    let targetAnchor = restingPosition(of: target, containerSize: containerSize)
                    piles.join(group, onto: target)
                    for id in piles.members(of: target) { positions[id] = targetAnchor }
                    Haptics.medium()
                    return
                }

                let landed = clamped(finalPoint, containerSize: containerSize)
                for id in group { positions[id] = landed }
            }
    }

    /// Where a tab's pile rests (its front's spot), or a free tab's own.
    private func restingPosition(of id: String, containerSize: CGSize) -> CGPoint {
        let front = piles.members(of: id).first ?? id
        if let stored = positions[front] { return stored }
        let index = manager.keptPosts.firstIndex(where: { $0.id == front }) ?? 0
        return defaultPosition(for: index, containerSize: containerSize)
    }

    /// The closest free bubble or pile front within the magnet radius.
    private func nearestTarget(to point: CGPoint, excluding group: [String], containerSize: CGSize) -> String? {
        manager.keptPosts.map(\.id)
            .filter { !group.contains($0) && piles.order(of: $0) == 0 }
            .map { ($0, distance(point, restingPosition(of: $0, containerSize: containerSize))) }
            .filter { $0.1 < Self.snapRadius }
            .min { $0.1 < $1.1 }?.0
    }

    /// Spreads a pile vertically around its spot, spaced wider than the
    /// magnet radius; with Magnetic Stacking on, the members still there
    /// spring back into the pile after a beat (Reborn's `fanOutStack:`).
    private func fanOut(_ stack: String, containerSize: CGSize? = nil, regathers: Bool = true) {
        guard let first = piles.piles[stack]?.first else { return }
        let size = containerSize ?? UIScreen.main.bounds.size
        let anchor = restingPosition(of: first, containerSize: size)
        let members = piles.disband(stack)
        let block = CGFloat(members.count - 1) * Self.fanSpacing
        let half = Self.bubbleSize / 2
        let minY = half + 40, maxY = size.height - half - 40
        let startY = max(minY, min(maxY - block, anchor.y - block / 2))
        for (i, id) in members.enumerated() {
            positions[id] = CGPoint(x: anchor.x, y: startY + CGFloat(i) * Self.fanSpacing)
        }
        Haptics.light()
        regatherGeneration += 1
        guard regathers, settings.magneticStacking, members.count >= 2 else {
            regatherGroup = []
            return
        }
        regatherGroup = members
        regatherAnchor = anchor
        let generation = regatherGeneration
        Task { @MainActor in
            try? await Task.sleep(for: Self.regatherDelay)
            guard generation == regatherGeneration, settings.magneticStacking,
                  dragTranslations.isEmpty, previewingPostID == nil else { return }
            let open = Set(manager.keptPosts.map(\.id))
            let back = regatherGroup.filter { open.contains($0) && !piles.isStacked($0) }
            regatherGroup = []
            guard back.count >= 2, let anchor = regatherAnchor else { return }
            piles.regather(back)
            for id in back { positions[id] = anchor }
            Haptics.light()
        }
    }

    @ViewBuilder
    private func dropZone(containerSize: CGSize) -> some View {
        let position = dropZonePosition(containerSize: containerSize)
        ZStack {
            Circle()
                .fill(hoveringDropZone ? Color.red.opacity(0.85) : Color.red.opacity(0.5))
                .frame(width: Self.dropZoneSize, height: Self.dropZoneSize)
            Image(systemName: "xmark")
                .font(.title3.bold())
                .foregroundStyle(.white)
        }
        .position(position)
        .accessibilityIdentifier("floatingPostTabs.dropZone")
        .transition(.opacity)
    }

    private func dropZonePosition(containerSize: CGSize) -> CGPoint {
        CGPoint(x: containerSize.width / 2, y: containerSize.height - 120)
    }

    private func defaultPosition(for index: Int, containerSize: CGSize) -> CGPoint {
        let baseX = containerSize.width - 44
        let baseY: CGFloat = 140 + CGFloat(index) * (Self.bubbleSize + 12)
        return CGPoint(x: baseX, y: min(baseY, containerSize.height - 160))
    }

    private func clamped(_ point: CGPoint, containerSize: CGSize) -> CGPoint {
        let half = Self.bubbleSize / 2
        return CGPoint(
            x: min(max(point.x, half), containerSize.width - half),
            y: min(max(point.y, half + 40), containerSize.height - half - 40)
        )
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// "Hold to Preview" wiring: `.onLongPressGesture`'s `perform:` only
/// fires once the press is held for the minimum duration without moving
/// too far, so `onHold` fires there. The `pressing:` callback fires
/// `false` on release however the gesture ended, so `onRelease` reports
/// `openedByHold: true` only when `perform` had already fired; a quick
/// tap falls through to the bubble's own `onTapGesture`, and a
/// hold-then-drag is cancelled by `DragGesture` taking over the touch.
private struct HoldToPreviewModifier: ViewModifier {
    let enabled: Bool
    let onHold: () -> Void
    let onRelease: (_ openedByHold: Bool) -> Void
    @State private var isHolding = false

    func body(content: Content) -> some View {
        if enabled {
            content.onLongPressGesture(minimumDuration: 0.35, maximumDistance: 12, pressing: { pressing in
                if !pressing {
                    let wasHolding = isHolding
                    isHolding = false
                    onRelease(wasHolding)
                }
            }, perform: {
                isHolding = true
                onHold()
            })
        } else {
            content
        }
    }
}

