import SwiftUI
import PhoebusCore

/// Reborn's "Custom API" screen: register your own Reddit OAuth client
/// ID, redirect URI and User-Agent. Never ships Apollo's credentials;
/// the copy steers toward registering a personal app
/// (reddit.com/prefs/apps).
public struct CustomAPISettingsScreen: View {
    @Setting(CustomAPISettingsStore.storage) private var settings

    public init() {}

    public var body: some View {
        List {
            Section {
                // Labelled "Reddit API Key" to match Reborn, not "Client ID".
                TextField("Reddit API Key", text: Binding(
                    get: { settings.redditClientID ?? "" },
                    set: { v in $settings.update { $0.redditClientID = v.isEmpty ? nil : v } }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .apolloSearchRow("Reddit API Key")
                TextField("Reddit API Secret (usually empty)", text: Binding(
                    get: { settings.redditClientSecret ?? "" },
                    set: { v in $settings.update { $0.redditClientSecret = v.isEmpty ? nil : v } }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .apolloSearchRow("Reddit API Secret (usually empty)")
                TextField("Redirect URI", text: Binding(
                    get: { settings.redditRedirectURI ?? "" },
                    set: { v in $settings.update { $0.redditRedirectURI = v.isEmpty ? nil : v } }
                ))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .apolloSearchRow("Redirect URI", lastBeforeFooter: true)
            } header: {
                Text("Reddit API")
                    .apolloSectionHeader()
            } footer: {
                Text("Reddit and Imgur no longer allow new API key creation for third-party apps. If you don't already have your own keys, Phoebus's default will be used instead.")
                    .apolloSectionFooter()
            }
            Section {
                TextField("User-Agent", text: Binding(
                    get: { settings.userAgent ?? "" },
                    set: { v in $settings.update { $0.userAgent = v.isEmpty ? nil : v } }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .apolloSearchRow("User-Agent", lastBeforeFooter: true)
            } footer: {
                Text("Recommended format: platform:app_id:version (by /u/your_username). A personalized value, rather than a shared default, helps avoid the kind of fingerprinting third-party Reddit clients have historically been targeted for.")
                    .apolloSectionFooter()
            }
            Section {
                TextField("Imgur Client ID", text: Binding(
                    get: { settings.imgurClientID ?? "" },
                    set: { v in $settings.update { $0.imgurClientID = v.isEmpty ? nil : v } }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .apolloSearchRow("Imgur Client ID")
                TextField("Img Chest API Key", text: Binding(
                    get: { settings.imgChestAPIKey ?? "" },
                    set: { v in $settings.update { $0.imgChestAPIKey = v.isEmpty ? nil : v } }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .apolloSearchRow("Img Chest API Key", lastBeforeFooter: true)
            } footer: {
                Text("Register your own app at api.imgur.com/oauth2/addclient, or your own Img Chest key at imgchest.com. Required for uploading images or viewing albums inline; Imgur no longer issues client IDs freely, so this may require sharing or reusing an existing one.")
                    .apolloSectionFooter()
            }
            Section {
                TextField("Giphy API Key", text: Binding(
                    get: { settings.giphyAPIKey ?? "" },
                    set: { v in $settings.update { $0.giphyAPIKey = v.isEmpty ? nil : v } }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .apolloSearchRow("Giphy API Key", lastBeforeFooter: true)
            } footer: {
                Text("Register your own app at developers.giphy.com. Required for the composer's GIF picker (search and trending GIFs).")
                    .apolloSectionFooter()
            }
            if settings != .default {
                Section {
                    Button("Reset to Defaults", role: .destructive) {
                        $settings.update { $0 = .default }
                    }
                    .apolloSearchRow("Reset to Defaults")
                }
            }
        }
        .apolloSettingsListAppearance()
        .navigationTitle("Custom API")
    }
}
