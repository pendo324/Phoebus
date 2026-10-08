import SwiftUI
import PhoebusCore

/// The "Kagi Session Link" sheet (Reborn "Kagi Search", #1305): where the
/// Search tab's Kagi mode gets the subscriber's Session Link (kagi.com →
/// Settings → Account → Session Link). Shown when Kagi is picked with no link
/// saved, and from the "Kagi Session Expired" card. Save checks the link with
/// Kagi (one account-page request, not a search) before storing it.
struct KagiSessionLinkSheet: View {
    /// Runs after a link Kagi accepted is saved and the sheet has closed.
    var onSaved: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var link = ""
    @State private var checking = false
    @State private var alert: Notice?
    @FocusState private var focused: Bool

    struct Notice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        /// Set when the link couldn't be checked: it may be kept anyway.
        var saveAnyway: String?

        static let notALink = Notice(
            title: "Not a Session Link",
            message: "Paste the whole Session Link from Kagi → Settings → Account. It starts with https://kagi.com/search?token=")
        static let rejected = Notice(
            title: "Kagi Didn't Accept This Link",
            message: "It may have expired or been reset. Copy a fresh Session Link from Kagi → Settings → Account.")
        static let keychain = Notice(
            title: "Couldn't Save the Link",
            message: "The Keychain didn't accept it. Try again, or restart Phoebus if this keeps happening.")
        static func unreachable(_ error: Error?, token: String) -> Notice {
            let reason = error?.localizedDescription ?? "Kagi didn't respond."
            return Notice(title: "Couldn't Reach Kagi", message: reason + " The link couldn't be checked.", saveAnyway: token)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://kagi.com/search?token=…", text: $link)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($focused)
                        .disabled(checking)
                        .onSubmit(save)
                        .accessibilityIdentifier("kagi.sessionLink.field")
                } footer: {
                    Text("In Kagi, open Settings → Account and copy your Session Link, then paste it here. Phoebus uses it to search Reddit with your Kagi account, and each page of results counts as one search on your plan. The link is kept in this device's Keychain.")
                }
                Section {
                    Button("Open Kagi Account Settings") {
                        focused = false
                        openURL(KagiSearch.sessionCheckURL)
                    }
                    .accessibilityIdentifier("kagi.sessionLink.openSettings")
                } footer: {
                    Text("Anyone with your Session Link can search as you. You can reset it in Kagi's account settings at any time.")
                }
            }
            .navigationTitle("Kagi Session Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(checking)
                        .accessibilityIdentifier("kagi.sessionLink.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if checking {
                        ProgressView()
                    } else {
                        Button("Save", action: save)
                            .disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("kagi.sessionLink.save")
                    }
                }
            }
            .alert(alert?.title ?? "", isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } }),
                   presenting: alert) { notice in
                if let token = notice.saveAnyway {
                    Button("Save Anyway") { store(token) }
                    Button("Cancel", role: .cancel) {}
                } else {
                    Button("OK", role: .cancel) {}
                }
            } message: { notice in
                Text(notice.message)
            }
        }
        .interactiveDismissDisabled(checking)
        .onAppear { focused = true }
    }

    private func save() {
        guard !checking else { return }
        guard let token = KagiSearch.normalizeSessionToken(link) else {
            alert = .notALink
            return
        }
        focused = false
        checking = true
        Task {
            let check = await KagiSearch.checkSession(token: token)
            checking = false
            switch check.result {
            case .valid: store(token)
            case .rejected: alert = .rejected
            case .unreachable: alert = .unreachable(check.error, token: token)
            }
        }
    }

    private func store(_ token: String) {
        guard KagiSession.setToken(token) else {
            alert = .keychain
            return
        }
        dismiss()
        onSaved()
    }
}
