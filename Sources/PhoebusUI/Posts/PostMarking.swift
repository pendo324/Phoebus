import SwiftUI
import PhoebusCore

/// Apollo's Mark NSFW / Mark Spoiler from a post menu. The new state is
/// announced at once (`PostMarkChange`) so every screen showing the post
/// updates, and announced back with Apollo's error if Reddit refuses.
@MainActor
enum PostMarking {
    static func toggle(_ mark: PostMark, on post: RedditPost, repository: RedditRepository) {
        let marking = !mark.isSet(on: post)
        NotificationCenter.default.post(PostMarkChange(fullname: post.name, mark: mark, value: marking).notification)
        Task {
            do {
                try await repository.setMark(mark, on: post.name, marked: marking)
            } catch {
                NotificationCenter.default.post(PostMarkChange(fullname: post.name, mark: mark, value: !marking).notification)
                ApolloToast.showError(mark.failureMessage(marking: marking), detail: UserFacingError.text(for: error))
            }
        }
    }
}

/// A Mark NSFW / Mark Spoiler menu row, titled for what it will do.
struct PostMarkMenuButton: View {
    let mark: PostMark
    let post: RedditPost
    let repository: RedditRepository
    let identifierPrefix: String

    var body: some View {
        Button {
            PostMarking.toggle(mark, on: post, repository: repository)
        } label: {
            Label(mark.title(marking: !mark.isSet(on: post)), systemImage: mark.symbol)
        }
        .accessibilityIdentifier("\(identifierPrefix).\(mark.rawValue)")
    }
}
