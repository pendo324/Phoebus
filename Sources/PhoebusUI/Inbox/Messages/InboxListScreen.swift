import SwiftUI
import PhoebusCore

/// Apollo's "Boxes" menu, the root of the Inbox tab, with Inbox (All)
/// pushed on top of it when the tab opens (see `InboxScreen`). Four
/// groups, as in Apollo: Inbox (All) and Unread; Post Replies, Comment
/// Replies and Mentions; Direct Chat and Messages; Moderator Mail.
/// Icons are Apollo's own `option-*` glyphs, Moderator Mail's in
/// moderator green.
public struct InboxListScreen: View {
    let repository: RedditRepository

    public init(repository: RedditRepository) {
        self.repository = repository
    }

    public var body: some View {
        List {
            Section {
                categoryRow(.inbox, title: "Inbox (All)", icon: "option-inbox")
                categoryRow(.unreadMessages, title: "Unread", icon: "option-unread-box")
            }
            Section {
                categoryRow(.postReplies, title: "Post Replies", icon: "option-posts")
                categoryRow(.commentReplies, title: "Comment Replies", icon: "option-comments")
                categoryRow(.usernameMentions, title: "Mentions", icon: "option-author")
            }
            Section {
                // Reddit Chat is Matrix underneath, so this is native
                // rather than a web view; see `RedditChatClient`.
                SettingsLink {
                    ChatListScreen(repository: repository)
                } label: {
                    BoxRowLabel(title: "Direct Chat", icon: "bubble.left.and.bubble.right")
                }
                .listRowBackground(Color.clear)
                .listSectionSeparator(.hidden)
                .accessibilityIdentifier("inbox.boxes.directChat")
                categoryRow(.messages, title: "Messages", icon: "option-mail")
            }
            Section {
                SettingsLink {
                    ModmailListScreen(repository: repository)
                } label: {
                    BoxRowLabel(title: "Moderator Mail", icon: "option-moderator",
                                tint: Color(hex: ApolloPalette.moderatorGreenHex))
                }
                .listRowBackground(Color.clear)
                .listSectionSeparator(.hidden)
                .accessibilityIdentifier("inbox.boxes.moderatorMail")
            }
        }
        .listStyle(.grouped)
        .scrollContentBackground(.hidden)
        .apolloStockSurface()
        .navigationTitle("Boxes")
        .navigationBarTitleDisplayModeIfAvailable()
    }

    private func categoryRow(_ category: InboxCategory, title: String, icon: String) -> some View {
        SettingsLink {
            InboxCategoryScreen(category: category, repository: repository)
        } label: {
            BoxRowLabel(title: title, icon: icon)
        }
        .listRowBackground(Color.clear)
        .listSectionSeparator(.hidden)
        .accessibilityIdentifier("inbox.boxes.\(category.rawValue)")
    }
}

/// A Boxes row: a 32pt icon column, then the title in 17pt, on the
/// page's own surface rather than a grouped card.
private struct BoxRowLabel: View {
    let title: String
    let icon: String
    var tint: Color = .apolloAccent

    var body: some View {
        HStack(spacing: 14) {
            ApolloIconImage(icon)
                .foregroundStyle(tint)
                .frame(width: 32)
            Text(title)
                .font(.system(size: 17))
        }
    }
}
