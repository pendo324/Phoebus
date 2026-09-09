import SwiftUI
import PhoebusCore

/// Sheet for reporting a post or comment to subreddit moderators, using Reddit's
/// standard reason set (spam/harassment/violence/etc.) plus a free-text "Other"
/// option.
public struct ReportSheet: View {
    let fullname: String
    let repository: RedditRepository
    let onComplete: () -> Void

    @State private var selectedReason: String?
    @State private var customReason = ""
    @State private var isSubmitting = false
    @Environment(\.dismiss) private var dismiss

    /// Reddit's standard site-wide report reasons, matching what
    /// Reddit's own apps present when a subreddit hasn't configured
    /// custom removal reasons.
    private static let standardReasons = [
        "Spam",
        "Harassment",
        "Threatening violence",
        "Hate",
        "Minor abuse or sexualization",
        "Sharing personal information",
        "Non-consensual intimate media",
        "Prohibited transaction",
        "Impersonation",
        "Copyright violation",
        "Vote manipulation",
        "Ban evasion",
        "Rule-breaking content",
    ]

    public init(fullname: String, repository: RedditRepository, onComplete: @escaping () -> Void) {
        self.fullname = fullname
        self.repository = repository
        self.onComplete = onComplete
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Why are you reporting this?") {
                    ForEach(Self.standardReasons, id: \.self) { reason in
                        Button {
                            selectedReason = reason
                        } label: {
                            HStack {
                                Text(reason).foregroundStyle(.primary)
                                Spacer()
                                if selectedReason == reason {
                                    Image(systemName: "checkmark").foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
                Section("Other") {
                    TextField("Describe the issue", text: $customReason)
                        .onChange(of: customReason) { _, newValue in
                            if !newValue.isEmpty { selectedReason = nil }
                        }
                }
            }
            .apolloFlatListAppearance()
            .navigationTitle("Report")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        Task { await submit() }
                    }
                    .disabled(isSubmitting || (selectedReason == nil && customReason.isEmpty))
                }
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        let reason = selectedReason ?? customReason
        try? await repository.report(fullname: fullname, reason: reason)
        onComplete()
        dismiss()
    }
}
