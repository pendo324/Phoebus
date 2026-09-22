import SwiftUI
import PhoebusCore

/// The compact (list) layout of `PostRow`.
extension PostRow {
    /// Apollo's default dense list row: subreddit name alone at the
    /// top, then the title with an inline flair-text chip, a
    /// "(domain.com)" line for link posts, the author on its own line,
    /// then a meta row with score/comments/time/award-icons/••• on the
    /// left and a vote-arrow column on the right.
    var compactBody: some View {
        HStack(alignment: .top, spacing: 8) {
            // "Voting Buttons Position" (`AppearanceSettings.votingButtonsPosition`):
            // when on the left edge, renders here ahead of the title;
            // the default right position renders after it.
            if showsVotingButtons, votingButtonsPosition == .left {
                voteArrowColumn
            }
            VStack(alignment: .leading, spacing: 3) {
                // Apollo renders a distinct banner for stickied posts,
                // separate from the rest of the info row.
                if post.stickied {
                    Label("Stickied Post", systemImage: "pin.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(.green)
                }

                // Subreddit above the title: structural on aggregate
                // feeds (always shown there), and also moved up inside
                // a specific subreddit by `ShowSubredditAtTop`. When
                // shown, the footer "subreddit by author" stack is
                // hidden and the author moves to its own line.
                if showsSubredditHeader {
                    // 6.7pt icon->text gap, 16pt icon.
                    HStack(spacing: 6.7) {
                        if showsSubredditIcon {
                            SubredditIconView(subreddit: post.subreddit, repository: repository, size: 16)
                        }
                        Text(SubredditCapitalization.display(post.subreddit))
                            // 15pt semibold, heavier than the 15pt
                            // regular title.
                            .apolloFont(size: 15, weight: .semibold)
                            .foregroundStyle(Color.apolloSecondaryText(colorScheme: colorScheme, themeColors: themeColors))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .contentShape(Rectangle())
                            .highPriorityGesture(TapGesture().onEnded(onSubredditTap))
                            .accessibilityIdentifier("feed.postRow.subredditHeader")
                        Spacer(minLength: 0)
                    }
                    // The list row's own 12.7pt top inset positions the header glyph.
                    .padding(.bottom, 3.7)
                }

                // Reddit renders the flair immediately after the last
                // word of the title, wrapping with it. `Text` can't
                // embed a `Capsule`-backed subview inline, so this uses
                // `FlowLayout` over the title's words plus the flair
                // chip as a final "word". The title is one attributed
                // string (not per-word with a set gap, which breaks
                // lines wrong). `TitleFlairLayout` measures the
                // title's last line with TextKit so the capsule
                // follows the final glyph when it fits, else wraps under it.
                TitleFlairLayout(titleString: titleMeasureString, fontSize: titleFontSize, bold: appearanceSettings.boldPostTitles, gap: 4, lineSpacing: 3) {
                    titleText
                        .fixedSize(horizontal: false, vertical: true)
                    // "Post Flair" toggle (Settings > Appearance > Flair).
                    let flair = generalSettings.showPostFlair ? post.linkFlairText.flatMap { $0.isEmpty ? nil : $0 } : nil
                    if post.over18 || flair != nil {
                    HStack(spacing: 4) {
                    if post.over18 { NSFWTag() }
                    if let flair {
                        LinkFlairLabel(text: flair, parts: post.linkFlairRichtext)
                            // 13pt regular in an 18pt-tall full
                            // capsule with 6pt side padding.
                            .apolloFont(size: 13)
                            .lineLimit(1)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 6)
                            .frame(height: 18)
                            .background(Capsule().fill(linkFlairBackgroundColor ?? Color.apolloFlairFill(colorScheme: colorScheme)))
                            .foregroundStyle(linkFlairTextColor ?? Color.apolloTertiaryText(colorScheme: colorScheme, themeColors: themeColors))
                    }
                    }
                    }
                }
                .tagFilterCover(.title, isNSFW: post.over18, isActive: coversTitle) { revealTagPart(.title) }
                // Reborn "Translate Post Titles" (see `TitleTranslation`).
                .apolloTranslatesTitle(post.title, into: $translatedTitle)
                if translatedTitle != nil, !shouldBlurTitle {
                    TitleTranslationMarker(original: post.title)
                }
                // `.lineLimit` has no effect on a `Layout` container (only on `Text`);
                // titles are short enough that row-counting truncation isn't needed.

                // The "(domain.com)" is NOT its own line: it is inline
                // at the end of the title in the same 15pt regular
                // font, tinted tertiary. See `titleText`.

                // Apollo's compact row merges subreddit and author
                // into one line: "[icon] Subreddit by Author", below
                // the title. Shown only when the subreddit is not at
                // the top; when it is, the author gets its own line.
                if !showsAuthorInInfoRow, !subredditLeadsInfoRow {
                HStack(spacing: 4) {
                    // Shown alongside the subreddit name whenever
                    // `inSpecificSubreddit == false`, i.e. exactly on
                    // the aggregate Home/Popular/All feeds.
                    if showsSubredditIcon, !showsSubredditHeader {
                        SubredditIconView(subreddit: post.subreddit, repository: repository, size: 16)
                    }
                    if !showsSubredditHeader {
                        // Apollo's display capitalization, not Reddit's
                        // lowercase URL form. See
                        // `SubredditCapitalization`.
                        Text(SubredditCapitalization.display(post.subreddit))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .contentShape(Rectangle())
                            .highPriorityGesture(TapGesture().onEnded(onSubredditTap))
                            .accessibilityIdentifier("feed.postRow.subredditLabel")
                    }
                    // "by author" only when Usernames is on.
                    if appearanceSettings.alwaysShowUsernames {
                        if !showsSubredditHeader {
                            Text("by")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(post.author)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .contentShape(Rectangle())
                            .highPriorityGesture(TapGesture().onEnded(onAuthorTap))
                            .accessibilityIdentifier("feed.postRow.authorLabel")
                    }

                    // The author's flair chip goes with the author's name: with Usernames
                    // off Apollo shows neither.
                    if appearanceSettings.alwaysShowUsernames, generalSettings.showUserFlair,
                       let authorFlair = post.authorFlairText, !authorFlair.isEmpty {
                        LinkFlairLabel(text: authorFlair, parts: nil)
                            .font(.caption2)
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(authorFlairBackgroundColor ?? Color.secondary.opacity(0.2)))
                            .foregroundStyle(authorFlairTextColor ?? .secondary)
                    }
                    // Reddit API field `author_cakeday`.
                    if post.authorCakeday == true {
                        Text("🎂").font(.caption2).accessibilityLabel("Cake day")
                    }
                }
                }

                HStack(spacing: 10) {
                    if showsAuthorInInfoRow {
                        infoRowAuthor
                    }
                    if subredditLeadsInfoRow {
                        infoRowSubreddit
                    }
                    infoRowStats
                    // The ••• is INLINE, 10pt after the age, not
                    // pushed to the trailing edge with a `Spacer`.
                    moreOptionsButton
                    Spacer(minLength: 0)
                }
                .lineLimit(1)
                .fixedSize(horizontal: false, vertical: true)
                // 13pt regular #94969C.
                .apolloFont(size: 13)
                .foregroundStyle(Color.apolloSecondaryText(colorScheme: colorScheme, themeColors: themeColors))
                // 11pt from the title block to the info row's glyph tops.
                .padding(.top, 4)
            }

            Spacer(minLength: 0)

            if generalSettings.thumbnailsOnLeft {
                thumbnailView
            }

            // Right edge (real default) - see the matching left-edge
            // `if` at the top of this HStack.
            if showsVotingButtons, votingButtonsPosition == .right {
                voteArrowColumn
            }
        }
    }

    /// The author at the head of the info row inside a subreddit: a 20pt
    /// picture 5pt from the name. With Show Subreddit at Top off and usernames
    /// hidden, the subreddit leads the info row instead, as in Apollo's Home
    /// feed.
    var subredditLeadsInfoRow: Bool {
        isAggregateFeed && !showsSubredditHeader && !appearanceSettings.alwaysShowUsernames
    }

    var infoRowSubreddit: some View {
        HStack(spacing: 5) {
            if showsSubredditIcon {
                SubredditIconView(subreddit: post.subreddit, repository: repository, size: 16)
            }
            Text(SubredditCapitalization.display(post.subreddit))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .layoutPriority(-1)
        .contentShape(Rectangle())
        .highPriorityGesture(TapGesture().onEnded(onSubredditTap))
        .accessibilityIdentifier("feed.postRow.subredditLabel")
    }

    var infoRowAuthor: some View {
        HStack(spacing: 5) {
            if generalSettings.showUserProfilePictures {
                AvatarView(username: post.author, repository: repository, size: 20)
            }
            Text(post.author)
                .lineLimit(1)
                .truncationMode(.tail)
            if post.authorCakeday == true {
                Text("🎂").accessibilityLabel("Cake day")
            }
        }
        .layoutPriority(-1)
        .contentShape(Rectangle())
        .highPriorityGesture(TapGesture().onEnded(onAuthorTap))
        .accessibilityIdentifier("feed.postRow.authorLabel")
    }

    var voteArrowColumn: some View {
        // `inline-upvote`/`inline-downvote`, 14.75x18.19pt, 12pt apart.
        VStack(spacing: 12) {
            Button {
                Task { await vote(direction: voteState == true ? 0 : 1) }
            } label: {
                StockIcon("inline-upvote")
                    .foregroundStyle(voteState == true ? .orange : Color.apolloIdleVoteArrow)
            }
            .accessibilityIdentifier("feed.postRow.upvote")
            .accessibilityLabel("Upvote")
            Button {
                Task { await vote(direction: voteState == false ? 0 : -1) }
            } label: {
                StockIcon("inline-downvote")
                    .foregroundStyle(voteState == false ? .blue : Color.apolloIdleVoteArrow)
            }
            .accessibilityIdentifier("feed.postRow.downvote")
            .accessibilityLabel("Downvote")
        }
        .buttonStyle(.plain)
        // Arrow top is 17.7pt below the separator.
        .padding(.top, 6.6)
    }
}

/// Apollo's NSFW tag after a post's title: "NSFW" in 13pt semibold white on
/// #D32D1E, 17pt tall with small corners.
struct NSFWTag: View {
    var body: some View {
        Text("NSFW")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .frame(height: 17)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(red: 211 / 255, green: 45 / 255, blue: 30 / 255)))
            .accessibilityLabel("NSFW")
    }
}

extension PostRow {
    /// The info row's score, comments, age, translation marker and awards,
    /// shared by the compact and large rows so every Info Row and
    /// Appearance setting applies to both.
    /// The stats, with Reborn's info-row magnifier over them.
    var infoRowStats: some View {
        HStack(spacing: 10) { infoRowStatItems }
            .coordinateSpace(name: InfoRowMagnifierProbe.space)
            .onPreferenceChange(InfoRowStatFrames.self) { infoRowStatFrames = $0 }
            .background(InfoRowMagnifierProbe(targets: infoRowStatFrames,
                                               enabled: infoRowSettings.magnifierOnHold,
                                               onActivate: activateInfoRowStat)
                // Its press lives on the cell; the view itself must not
                // take the stats' taps.
                .allowsHitTesting(false))
            .alert(ageDetail?.title ?? "", isPresented: $ageDetail.isPresent()) {
                Button("OK", role: .cancel) {}
            } message: {
                if let message = ageDetail?.message { Text(message) }
            }
    }

    /// What releasing the magnifier on a stat does; a stat whose Info Row
    /// action is off does nothing, as Reborn's.
    func activateInfoRowStat(_ stat: InfoRowStat) {
        switch stat {
        case .score: infoRowScoreTapped()
        case .comments:
            if infoRowSettings.tapToComments { onCommentsTap?() }
        case .age: showAgeDetail()
        case .translation:
            if infoRowSettings.tapToTranslation { onTranslateTap?() }
        }
    }

    /// Info Row Popup: the post's age as Reborn's alert; Overlay: as its
    /// small card over the age, which fades after 1.6 s.
    func showAgeDetail() {
        if infoRowSettings.overlayMode {
            let lines = InfoRowAgeDetail.lines(created: post.created, condensed: true)
            let card = AgeDetail(title: lines.title, message: lines.message)
            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) { ageOverlay = card }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.6))
                guard ageOverlay?.id == card.id else { return }
                withAnimation(.easeIn(duration: 0.35)) { ageOverlay = nil }
            }
        } else if infoRowSettings.popupMode {
            let lines = InfoRowAgeDetail.lines(created: post.created)
            ageDetail = AgeDetail(title: lines.title, message: lines.message)
        }
    }

    @ViewBuilder
    var infoRowStatItems: some View {
            // Info Row tap-to-upvote/magnify/popup-detail
            // (`UDKeyInfoRowTapUpvote`, `UDKeyIconRowMagnifier`,
            // `UDKeyInfoRowPopupMode`/`UDKeyInfoRowOverlayMode`).
            // Uses `highPriorityGesture` so it wins over the
            // row's own `.onTapGesture`. Apollo's own
            // `posts-points` glyph (10x12pt), not SF
            // `arrow.up`, with a 4pt icon->number gap.
            HStack(spacing: 4) {
                StockIcon("posts-points")
                Text(displayScore.apolloAbbreviated)
            }
                .infoRowStat(.score)
                .contentShape(Rectangle())
                .highPriorityGesture(TapGesture().onEnded {
                    guard !InfoRowHoldRecognizer.tapFollowsHold else { return }
                    infoRowScoreTapped()
                })
                .onLongPressGesture(minimumDuration: 0.35, perform: infoRowScoreLongPressed)
                .popover(isPresented: $showingInfoRowDetail) {
                    VoteBreakdownView(score: post.score, upvoteRatio: post.upvoteRatio)
                        .padding()
                        .presentationCompactAdaptation(.popover)
                }
            // "% Upvoted" removed from feed rows: it's a
            // post-detail element, not shown in list rows.
            // Info Row tap-to-comments jumps to comments via
            // `onCommentsTap` when the setting is on, else
            // falls through to the row's default open-post tap.
            // Always shown, as Apollo (Show Comments Button is the
            // in-app browser's button).
            HStack(spacing: 4) {
                // `posts-comments`, 14x13pt. The blue dot
                // is a badge overlay pinned to the
                // bubble's top-right when the thread has
                // grown since the last visit.
                StockIcon("posts-comments")
                    .overlay(alignment: .topTrailing) {
                        // The dot is New Comments Highlightifier's; the "+ N" below shows either
                        // way, as in Apollo.
                        if newCommentCount > 0, generalSettings.newCommentsHighlightifier {
                            Circle()
                                .fill(Color(hex: "3165A6"))
                                .frame(width: 6, height: 6)
                                .offset(x: 3, y: -3)
                        }
                    }
                Text(post.numComments.apolloAbbreviated)
                // "+ N" pill, 13pt #3165A6 on #071420, 16pt tall.
                if newCommentCount > 0 {
                    Text("+ \(newCommentCount.apolloAbbreviated)")
                        .apolloFont(size: 13)
                        .foregroundStyle(Color(hex: "3165A6"))
                        .padding(.horizontal, 4)
                        .frame(height: 16)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: "071420")))
                        .padding(.leading, 6)
                        .accessibilityIdentifier("feed.postRow.unreadComments")
                }
            }
                .contentShape(Rectangle())
                .highPriorityGesture(
                    TapGesture().onEnded {
                        guard !InfoRowHoldRecognizer.tapFollowsHold,
                              infoRowSettings.tapToComments, let onCommentsTap else { return }
                        onCommentsTap()
                    },
                    including: infoRowSettings.tapToComments && onCommentsTap != nil ? .all : .subviews
                )
                .accessibilityIdentifier("feed.postRow.commentsLabel")
                .infoRowStat(.comments)
            TimestampLabel(post.created, showsIcon: true)
                .infoRowStat(.age)
                // Info Row Overlay: the card sits just above the age.
                .overlay(alignment: .top) {
                    // A zero-height line at the age's top, the card resting on it.
                    Color.clear.frame(height: 0).overlay(alignment: .bottom) {
                        if let card = ageOverlay {
                            InfoRowOverlayCard(title: card.title, message: card.message)
                                .padding(.bottom, 8)
                                .transition(.opacity.combined(with: .offset(y: 6)))
                                .id(card.id)
                        }
                    }
                }
                .zIndex(1)
                .contentShape(Rectangle())
                // Info Row Popup/Overlay: tapping the age shows when it was posted.
                .highPriorityGesture(TapGesture().onEnded {
                    guard !InfoRowHoldRecognizer.tapFollowsHold else { return }
                    showAgeDetail()
                },
                                     including: infoRowSettings.popupMode || infoRowSettings.overlayMode ? .all : .subviews)
            // Info Row "Translation" marker: the 🌐 marker
            // beside a post's stats. Tapping it translates the
            // title/body via the translator sheet. Appears
            // only when Translation settings enable it.
            if infoRowSettings.tapToTranslation, InfoRowSettings.translationAvailable {
                Button {
                    guard !InfoRowHoldRecognizer.tapFollowsHold else { return }
                    onTranslateTap?()
                } label: {
                    Text("🌐")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("feed.postRow.translateMarker")
                .accessibilityLabel("Translate post")
                .infoRowStat(.translation)
            }
            // "Show Awards" toggle (Settings > Appearance > Other).
            if generalSettings.showAwards, let awards = post.totalAwardsReceived, awards > 0 {
                Label("\(awards)", systemImage: "medal.fill")
                    .foregroundStyle(.yellow)
            }
    }
}
