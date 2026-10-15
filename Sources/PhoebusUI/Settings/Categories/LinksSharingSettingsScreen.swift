import SwiftUI
import PhoebusCore

/// Links & Sharing: where a link opens, what it shares as, and where
/// uploads go. Apollo's General Safari rows and browser choice, its
/// share and tweet rows, and Reborn's Media sharing and upload hosts are
/// its sections. Open in App and the link-preview cards are drill-downs.
public struct LinksSharingSettingsScreen: View {
    @Setting(GeneralSettingsStore.storage) private var settings
    @Setting(CustomAPISettingsStore.storage) private var customAPI
    /// Reborn refuses an upload host without its API key. Each picker
    /// presents its own alert.
    @State private var uploadHostKeyRequired: (title: String, message: String)?
    @State private var commentHostKeyRequired: (title: String, message: String)?

    public init() {}

    private func hasKey(_ key: String?) -> Bool {
        !(key ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var apiKeysPath: String {
        SettingsCategory.accountsSecurity.path(section: "API Keys")
    }

    public var body: some View {
        List {
            ExternalBrowserSections()
            inAppBrowserSection
            otherAppsSection
            sharingSection
            uploadsSection
            linkPreviewsSection
        }
        .apolloSettingsSearchScroll()
        .apolloSettingsListAppearance()
        .navigationTitle(SettingsCategory.linksSharing.title)
        .navigationBarTitleDisplayModeIfAvailable()
    }

    private var inAppBrowserSection: some View {
        Section {
            Toggle("Always Use Reader Mode", isOn: $settings.alwaysUseReaderMode)
                .apolloSearchRow("Always Use Reader Mode")
            Toggle("Show Comments Button", isOn: $settings.showCommentsButton)
                .apolloSearchRow("Show Comments Button")
        } header: {
            Text("In-App Browser")
                .apolloSectionHeader()
        }
    }

    private var otherAppsSection: some View {
        Section {
            ApolloSettingsPicker("Open Tweets in", selection: $settings.openTwitterLinksIn,
                                 options: TwitterLinkDestination.allCases.map { $0 },
                                 display: { $0.displayName })
                .apolloSearchRow("Open Tweets in")
            SettingsDrillDownRow(destination: .openInApp)
        } header: {
            Text("Other Apps")
                .apolloSectionHeader()
        }
    }

    private var sharingSection: some View {
        Section {
            Toggle("Share Includes Title", isOn: $settings.sharePostIncludesTitle)
                .apolloSearchRow("Share Includes Title")
            // Stock's own switch; a Share Link Host other than Reddit
            // still wins (`effectiveShareLinkHost`).
            Toggle("Share old.reddit Links", isOn: $settings.shareOldRedditLinks)
                .apolloSearchRow("Share old.reddit Links")
            ApolloSettingsPicker("Share Link Host", selection: $settings.shareLinkHost,
                                 options: ShareLinkHost.allCases.map { $0 },
                                 display: { $0.displayName },
                                 showsChevron: true)
                .apolloSearchRow("Share Link Host", lastBeforeFooter: true)
        } header: {
            Text("Sharing")
                .apolloSectionHeader()
        } footer: {
            Text("Choose which Reddit host Phoebus uses for shared post and comment links, including Copy Link and links included with shared media. fxReddit uses fxddit.com.")
                .apolloSectionFooter()
        }
    }

    private var uploadsSection: some View {
        Section {
            ApolloSettingsPicker("Media Upload Host", selection: Binding(
                                     get: { settings.mediaUploadHost },
                                     set: { host in
                                         if host == .imgChest, !hasKey(customAPI.imgChestAPIKey) {
                                             uploadHostKeyRequired = ("Image Chest API Key Required",
                                                                      "Add your Image Chest API key under \(apiKeysPath) first, then select Image Chest as the upload host.")
                                         } else {
                                             $settings.mediaUploadHost.wrappedValue = host
                                         }
                                     }),
                                 options: MediaUploadHost.allCases.map { $0 },
                                 display: { $0.displayName },
                                 showsChevron: true)
                .apolloSearchRow("Media Upload Host")
                .alert(uploadHostKeyRequired?.title ?? "", isPresented: Binding(get: { uploadHostKeyRequired != nil }, set: { if !$0 { uploadHostKeyRequired = nil } })) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(uploadHostKeyRequired?.message ?? "")
                }
            ApolloSettingsPicker("Comment Link Host", selection: Binding(
                                     get: { settings.commentLinkHost },
                                     set: { host in
                                         if host == .imgur, !hasKey(customAPI.imgurClientID) {
                                             commentHostKeyRequired = ("Imgur API Key Required",
                                                                       "Add your Imgur API key under \(apiKeysPath) first, then select Imgur as the comment link host.")
                                         } else if host == .imgChest, !hasKey(customAPI.imgChestAPIKey) {
                                             commentHostKeyRequired = ("Image Chest API Key Required",
                                                                       "Add your Image Chest API key under \(apiKeysPath) first, then select Image Chest as the comment link host.")
                                         } else {
                                             $settings.commentLinkHost.wrappedValue = host
                                         }
                                     }),
                                 options: CommentLinkHost.allCases.map { $0 },
                                 display: { $0.displayName },
                                 showsChevron: true)
                .apolloSearchRow("Comment Link Host", lastBeforeFooter: settings.commentLinkHost == .off)
                .alert(commentHostKeyRequired?.title ?? "", isPresented: Binding(get: { commentHostKeyRequired != nil }, set: { if !$0 { commentHostKeyRequired = nil } })) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(commentHostKeyRequired?.message ?? "")
                }
            if settings.commentLinkHost != .off {
                Toggle("Prefer Native Images", isOn: $settings.commentLinkPreferNative)
                    .apolloSearchRow("Prefer Native Images", lastBeforeFooter: true)
            }
        } header: {
            Text("Uploads")
                .apolloSectionHeader()
        } footer: {
            Text("Media Upload Host chooses where images you attach to posts and comments are uploaded.\n\nComment Link Host uploads comment images to Imgur or Image Chest and inserts a plain link, so they work in subreddits that don't allow image comments. Prefer Native Images uses Reddit's own image upload wherever the subreddit allows it, and the link host only where it doesn't.\n\nManage past uploads under \(SettingsCategory.path(to: .deleteImgurUploads)).")
                .apolloSectionFooter()
        }
    }

    private var linkPreviewsSection: some View {
        Section {
            SettingsDrillDownRow(destination: .linkPreview)
        } header: {
            Text("Link Previews")
                .apolloSectionHeader()
        }
    }
}
