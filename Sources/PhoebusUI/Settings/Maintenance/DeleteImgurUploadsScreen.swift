import SwiftUI
import PhoebusCore

/// Apollo's "Manage Uploads" screen for Imgur: view or delete media
/// uploaded through the app, with the delete hash available for manual
/// deletion at imgur.com/delete/<hash>. Reached from the Settings
/// "Manage Uploads" row.
public struct DeleteImgurUploadsScreen: View {
    @State private var records: [ImgurUploadRecord] = ImgurUploadHistoryStore.load()
    @State private var deletionError: String?
    @State private var copiedHashAlert = false
    /// Uploads chosen to delete, waiting for the confirmation: this
    /// deletes from Imgur itself, so it is not a one-tap swipe.
    @State private var pendingDeletion: IndexSet?

    public init() {}

    public var body: some View {
        List {
            if records.isEmpty {
                Section {
                    Text("No media uploads to manage.\n\nOnce uploaded (cool pics of your turtle maybe?), items will show here and you can manage them.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(records) { record in
                        HStack(alignment: .top, spacing: 12) {
                            CachedAsyncImage(url: URL(string: record.image.link))
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.image.id)
                                    .font(.subheadline)
                                Text(record.uploadedAt, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contextMenu {
                            if let hash = record.image.deleteHash {
                                Button("Copy Delete Hash") {
                                    #if canImport(UIKit)
                                    UIPasteboard.general.string = hash
                                    #endif
                                    copiedHashAlert = true
                                }
                            }
                        }
                    }
                    .onDelete { offsets in pendingDeletion = offsets }
                } footer: {
                    Text("Media you've uploaded to Imgur. View or delete, deleting will remove your upload from Imgur.")
                    .apolloSectionFooter()
                }
            }
        }
        .apolloFlatListAppearance()
        .navigationTitle("Manage Imgur Uploads")
        .alert("Copied Delete Hash", isPresented: $copiedHashAlert) {
            Button("OK", role: .cancel) {}
        }
        .alert("Delete \(pendingDeletion?.count == 1 ? "This Upload" : "\(pendingDeletion?.count ?? 0) Uploads")?",
               isPresented: Binding(get: { pendingDeletion != nil },
                                    set: { if !$0 { pendingDeletion = nil } })) {
            Button("Delete", role: .destructive) {
                if let offsets = pendingDeletion { delete(at: offsets) }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("This removes the upload from Imgur. The delete hash is in the row's context menu if you'd rather delete it there.")
        }
        .alert("Error Deleting Upload", isPresented: .constant(deletionError != nil)) {
            Button("OK", role: .cancel) { deletionError = nil }
        } message: {
            Text(deletionError ?? "")
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let record = records[index]
            guard let hash = record.image.deleteHash else { continue }
            Task {
                do {
                    try await ImgurClient.deleteImage(deleteHash: hash)
                    await MainActor.run {
                        records = ImgurUploadHistoryStore.load()
                    }
                } catch {
                    // Matches Apollo's own error copy verbatim.
                    await MainActor.run {
                        deletionError = "There was an error deleting the upload, sorry. You can retry shortly, or long-press on the upload row to copy the delete hash to your clipboard, then you can manually delete it yourself by going to imgur.com/delete/<deletehash> in a web browser, or you can contact the developer if it keeps happening."
                    }
                }
            }
        }
    }
}
