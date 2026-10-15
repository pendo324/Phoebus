import SwiftUI
import PhoebusCore

/// "Blocked Users" (`Settings → Filters`): the account's
/// Reddit block list, as Apollo's. Swipe to unblock; "Block User…" adds.
struct BlockedUsersScreen: View {
    @Setting(BlockedUsersStore.storage) private var stored
    @State private var errorMessage: String?
    @State private var showingAdd = false
    @State private var newName = ""

    private var names: [String] { BlockedUsersStore.names() }

    var body: some View {
        List {
            Section {
                if names.isEmpty {
                    Text("No blocked users.").foregroundStyle(.secondary)
                }
                ForEach(names, id: \.self) { name in
                    Text(name).apolloPlainSettingsRowInsets()
                }
                .onDelete { indexSet in
                    let removed = indexSet.map { names[$0] }
                    Task {
                        for name in removed {
                            do {
                                try await ActiveRedditRepository.provider()?.unblockUser(username: name)
                            } catch {
                                errorMessage = UserFacingError.text(for: error)
                            }
                        }
                    }
                }
                Button("Block User…") { showingAdd = true }
                    .foregroundStyle(Color.apolloAccent)
                    .apolloPlainSettingsRowInsets(rule: false)
            }
        }
        .apolloSettingsListAppearance()
        .navigationTitle("Blocked Users")
        .task { await refresh() }
        .refreshable { await refresh() }
        .alert("Block User", isPresented: $showingAdd) {
            TextField("Username", text: $newName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) { newName = "" }
            Button("Block") {
                let name = newName.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "u/", with: "")
                newName = ""
                guard !name.isEmpty else { return }
                Task {
                    do { try await ActiveRedditRepository.provider()?.blockUser(username: name) }
                    catch { errorMessage = UserFacingError.text(for: error) }
                }
            }
        }
        .alert("Blocked Users", isPresented: $errorMessage.isPresent()) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func refresh() async {
        guard let repository = ActiveRedditRepository.provider() else { return }
        do { try await repository.fetchBlockedUsers() }
        catch { errorMessage = UserFacingError.text(for: error) }
    }
}
