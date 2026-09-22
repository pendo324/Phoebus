import SwiftUI
import PhoebusCore

/// Reborn's author-only "Comment Insights".
///
/// Reddit's OAuth comment model has no upvote ratio and fuzzes the score,
/// so the data comes from the server-rendered `/commentstats/t1_<id>`
/// page, which renders for the comment's author. See
/// `CommentVoteInsightsClient`.
struct CommentVoteInsightsSheet: View {
    let comment: RedditComment
    let repository: RedditRepository

    @Environment(\.dismiss) private var dismiss
    @State private var outcome: CommentVoteInsightsClient.Outcome?
    @State private var isLoading = true
    @State private var needsWebSession = false

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if needsWebSession {
                    // Eligibility does not require a stored session, so this can explain
                    // how to enable it rather than silently doing nothing.
                    Text("Comment Insights needs a Reddit web session. Sign in without an API key, or add a web session under Accounts, and try again.")
                        .foregroundStyle(.secondary)
                } else if case .insight(let insight)? = outcome {
                    Section {
                        if let percent = insight.upvotePercent {
                            LabeledContent("Upvote Ratio", value: "\(formatted(percent))%")
                                .accessibilityIdentifier("insights.ratio")
                        }
                        if let upvotes = insight.reportedUpvotes {
                            LabeledContent("Upvotes") {
                                // Reddit sometimes abbreviates the label ("1.2k upvotes"), so the
                                // exact number is unknown; say so rather than showing a rounded value
                                // as exact.
                                Text(insight.reportedUpvotesAreAbbreviated
                                     ? "≈\(upvotes.formatted())"
                                     : upvotes.formatted())
                            }
                            .accessibilityIdentifier("insights.upvotes")
                        }
                        LabeledContent("Score Shown", value: comment.score.formatted())
                    } footer: {
                        // Reddit fuzzes the score, so the two figures can disagree.
                        Text("Reddit fuzzes the score shown in threads, so it can differ from the upvotes reported here.")
                    .apolloSectionFooter()
                    }
                } else if case .unavailable(let reason)? = outcome {
                    // Reddit's own sentence, shown verbatim: old comments get an
                    // "Insights unavailable" page (insights last 90 days), and
                    // paraphrasing would lose the actionable part.
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Insights unavailable for this comment.")
                        Text(reason)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("insights.unavailable")
                } else if outcome == .notReported {
                    Text("Reddit didn't report any vote details for this comment.")
                        .foregroundStyle(.secondary)
                } else {
                    // Reddit sometimes answers with HTTP 200 and a bot-check page, which
                    // is distinct from "no data".
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reddit didn't return the stats page.")
                        Text("It answers some requests with a browser check instead. Try again, or re-harvest your web session under Accounts.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Button("Try Again") {
                        Task { await load() }
                    }
                    .accessibilityIdentifier("insights.retry")
                }
            }
            .apolloFlatListAppearance()
            .navigationTitle("Vote Insights")
            .navigationBarTitleDisplayModeIfAvailable()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard await repository.hasWebFeatureSession() else {
            needsWebSession = true
            return
        }
        needsWebSession = false
        outcome = await repository.fetchCommentVoteInsights(commentID: comment.id)
    }

    private func formatted(_ percent: Double) -> String {
        percent == percent.rounded()
            ? String(Int(percent))
            : String(format: "%.1f", percent)
    }
}
