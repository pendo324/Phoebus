import SwiftUI
import PhoebusCore

/// Apollo's award gifting screen: gives an award (spending the user's existing
/// Reddit Coins balance; this app never sells or purchases coins) to a post or
/// comment.
public struct AwardGiftingScreen: View {
    let fullname: String
    let repository: RedditRepository
    let onComplete: () -> Void

    @State private var selectedAward: RedditAward?
    @State private var isAnonymous = false
    @State private var message = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    /// Reddit's standard award set and their Coin costs, since no public endpoint
    /// lists a post's available awards without an active session.
    struct RedditAward: Identifiable, Hashable {
        let id: String
        let name: String
        let coinPrice: Int
        let icon: String
    }

    static let standardAwards: [RedditAward] = [
        RedditAward(id: "award_silver", name: "Silver", coinPrice: 100, icon: "star.circle"),
        RedditAward(id: "award_helpful", name: "Helpful", coinPrice: 150, icon: "hand.raised.circle"),
        RedditAward(id: "award_wholesome", name: "Wholesome", coinPrice: 150, icon: "heart.circle"),
        RedditAward(id: "award_gold", name: "Gold", coinPrice: 500, icon: "medal"),
        RedditAward(id: "award_platinum", name: "Platinum", coinPrice: 1800, icon: "crown"),
    ]

    public init(fullname: String, repository: RedditRepository, onComplete: @escaping () -> Void) {
        self.fullname = fullname
        self.repository = repository
        self.onComplete = onComplete
    }

    public var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
                Section("Choose an Award") {
                    ForEach(Self.standardAwards) { award in
                        Button {
                            selectedAward = award
                        } label: {
                            HStack {
                                Image(systemName: award.icon)
                                Text(award.name)
                                Spacer()
                                Text("\(award.coinPrice) coins").foregroundStyle(.secondary)
                                if selectedAward == award {
                                    Image(systemName: "checkmark").foregroundStyle(.blue)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
                Section {
                    Toggle("Give Anonymously", isOn: $isAnonymous)
                    // Mirrors Apollo's giveAward(anonymously:message:award:): an optional note
                    // sent alongside the award.
                    TextField("Add a message (optional)", text: $message, axis: .vertical)
                } footer: {
                    Text("Awards spend your existing Reddit Coins balance. This app does not sell or purchase Coins — visit reddit.com to buy Coins if you don't have any.")
                    .apolloSectionFooter()
                }
            }
            .apolloFlatListAppearance()
            .navigationTitle("Give Award")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Give") {
                        Task { await give() }
                    }
                    .disabled(selectedAward == nil || isSubmitting)
                }
            }
        }
    }

    private func give() async {
        guard let selectedAward else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await repository.giveAward(fullname: fullname, awardID: selectedAward.id, isAnonymous: isAnonymous, message: message)
            onComplete()
            dismiss()
        } catch {
            errorMessage = "Couldn't give award: \(error). This usually means you don't have enough Coins."
        }
    }
}
