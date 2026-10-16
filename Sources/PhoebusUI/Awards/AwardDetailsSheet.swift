import SwiftUI
import PhoebusCore

/// The breakdown behind an award pill: totals, then each award with its
/// count and gold, and the top awarders. Built from the award dialog and the
/// signed leaderboard link it names (two requests, only when opened).
struct AwardDetailsSheet: View {
    let thingID: String
    let repository: RedditRepository

    @Environment(\.dismiss) private var dismiss
    @State private var board: AwardLeaderboard?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            List {
                if let board {
                    content(board)
                } else if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .accessibilityIdentifier("awards.details.loading")
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Couldn't load the awards.")
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("awards.details.error")
                    Button("Try Again") { Task { await load() } }
                        .accessibilityIdentifier("awards.details.retry")
                }
            }
            .apolloFlatListAppearance()
            .navigationTitle("Awards")
            .navigationBarTitleDisplayModeIfAvailable()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("awards.details.done")
                }
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func content(_ board: AwardLeaderboard) -> some View {
        Section {
            if let total = board.totalAwards {
                LabeledContent("Awards", value: total.formatted())
                    .accessibilityIdentifier("awards.details.total")
            }
            if let gold = board.totalGold {
                LabeledContent("Gold", value: gold.formatted())
                    .accessibilityIdentifier("awards.details.gold")
            }
        }
        if board.tallies.isEmpty {
            Text("No awards yet.").foregroundStyle(.secondary)
        } else {
            let featured = board.featured?.id
            Section {
                ForEach(board.tallies) { tally in
                    HStack(spacing: 12) {
                        CachedAsyncImage(url: tally.iconURL, downsampleTarget: .pixelWidth(40, scale: 3))
                            .frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tally.name)
                            Text(tally.isFree ? "Free" : "\(tally.gold.formatted()) Gold")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(tally.count.formatted())
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("awards.details.row.\(tally.id)")
                    .listRowBackground(tally.id == featured ? Color.secondary.opacity(0.12) : nil)
                }
            } header: {
                Text("Awards").apolloSectionHeader()
            }
        }
        if !board.topAwarders.isEmpty {
            Section {
                ForEach(Array(board.topAwarders.enumerated()), id: \.offset) { _, giver in
                    LabeledContent(giver.username.map { "u/\($0)" } ?? "[anonymous]", value: "\(giver.gold.formatted()) Gold")
                }
            } header: {
                Text("Top Awarders").apolloSectionHeader()
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let dialog = try await repository.awardDialog(thingID: thingID)
            board = try await repository.awardLeaderboard(dialog: dialog)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
