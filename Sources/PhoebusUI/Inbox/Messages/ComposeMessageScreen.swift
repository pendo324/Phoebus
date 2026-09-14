import SwiftUI
import PhoebusCore

/// Composes a new private message to a given or user-entered username.
public struct ComposeMessageScreen: View {
    let repository: RedditRepository
    let onSent: () -> Void

    @State private var to: String
    @State private var subject = ""
    @State private var messageBody = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    /// Reddit's subject-line limit for both private messages and "message
    /// the moderators" (same `/api/compose` endpoint).
    static let maxSubjectLength = 100

    public init(to: String = "", repository: RedditRepository, onSent: @escaping () -> Void) {
        _to = State(initialValue: to)
        self.repository = repository
        self.onSent = onSent
    }

    public var body: some View {
        crashTrackedBody.onAppear { CrashRecorder.record(.openedComposer) }
    }

    @ViewBuilder private var crashTrackedBody: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
                Section {
                    TextField("Username", text: $to)
                        .autocorrectionDisabled()
                    // Reborn's live character counter for the Message Moderators/Compose
                    // subject field (100 characters).
                    TextField("Subject", text: $subject)
                        .onChange(of: subject) { _, newValue in
                            if newValue.count > Self.maxSubjectLength {
                                subject = String(newValue.prefix(Self.maxSubjectLength))
                            }
                        }
                    HStack {
                        Spacer()
                        Text("\(subject.count)/\(Self.maxSubjectLength)")
                            .font(.caption2)
                            .foregroundStyle(subject.count >= Self.maxSubjectLength ? .red : .secondary)
                    }
                }
                Section {
                    TextEditor(text: $messageBody)
                        .frame(minHeight: 150)
                }
            }
            .apolloFlatListAppearance()
            .navigationTitle("New Message")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        Task { await send() }
                    }
                    .disabled(isSubmitting || to.isEmpty || subject.isEmpty || messageBody.isEmpty)
                }
            }
        }
    }

    private func send() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await repository.sendPrivateMessage(to: to, subject: subject, body: messageBody)
            onSent()
            dismiss()
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }
}
