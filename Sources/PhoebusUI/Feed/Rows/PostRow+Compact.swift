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
                    }
                    }
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
        }
    }

    /// The author at the head of the info row inside a subreddit: a 20pt
    /// picture 5pt from the name. With Show Subreddit at Top off and usernames
    /// hidden, the subreddit leads the info row instead, as in Apollo's Home
    /// feed.
    var subredditLeadsInfoRow: Bool {
        isAggregateFeed && !showsSubredditHeader && !appearanceSettings.alwaysShowUsernames
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
            .alert(ageDetail?.title ?? "", isPresented: $ageDetail.isPresent()) {
                Button("OK", role: .cancel) {}
            } message: {
                if let message = ageDetail?.message { Text(message) }
            }
    }
    @ViewBuilder
    var infoRowStatItems: some View {
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
                .accessibilityIdentifier("feed.postRow.commentsLabel")
            TimestampLabel(post.created, showsIcon: true)
                .contentShape(Rectangle())
            // "Show Awards" toggle (Settings > Appearance > Other).
            if generalSettings.showAwards, let awards = post.totalAwardsReceived, awards > 0 {
                Label("\(awards)", systemImage: "medal.fill")
                    .foregroundStyle(.yellow)
            }
    }
}
