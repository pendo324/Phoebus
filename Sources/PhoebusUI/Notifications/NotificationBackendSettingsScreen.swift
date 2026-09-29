import SwiftUI
import PhoebusCore
#if canImport(UIKit)
import UIKit
#endif

/// Reborn's "Notification Backend" sub-screen, with real networking behind every
/// row (`PushNotificationClient`):
///
///  - "Test Connection" hits `GET /v1/health` on the self-hosted `apollo-backend`.
///  - "Test Bark Notification" POSTs straight to the Bark push URL, bypassing the
///    backend.
///  - "Register Device" registers this device (Bark transport, since a
///    free-Apple-ID sideload has no APNs entitlement) and every API-key account
///    with the backend, which polls Reddit and pushes inbox replies, mentions,
///    messages and watcher hits.
///  - "Send Test from Backend" asks the backend to push its own test through Bark,
///    proving the whole chain.
///  - "Unregister Device" deletes this device from the backend.
public struct NotificationBackendSettingsScreen: View {
    @Setting(NotificationSettings.self) private var notificationSettings
    @Setting(CustomAPISettings.self) private var customAPISettings
    @Setting(NotificationBackendSettingsStore.storage) private var settings
    @State private var alertMessage: String?
    @State private var busy = false
    @Environment(\.accountManager) private var accountManager

    public init() {}

    public var body: some View {
        List {
            Section {
                TextField("Backend URL", text: Binding(
                    get: { settings.backendURL ?? "" },
                    set: { v in $settings.update { $0.backendURL = v.isEmpty ? nil : v } }
                ), prompt: Text("https://apollo.example.com"))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .apolloSearchRow("Backend URL")

                TextField("Registration Token", text: Binding(
                    get: { settings.registrationToken ?? "" },
                    set: { v in $settings.update { $0.registrationToken = v.isEmpty ? nil : v } }
                ), prompt: Text("(optional)"))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .apolloSearchRow("Registration Token")

                Toggle("Bark Delivery", isOn: Binding(
                    get: { settings.barkEnabled },
                    set: { on in
                        let wasRegistered = PushRegistrationState.isRegistered(settings)
                        $settings.barkEnabled.wrappedValue = on
                        Task { await barkDeliveryChanged(on, wasRegistered: wasRegistered) }
                    }))
                    .apolloSearchRow("Bark Delivery")

                // Always shown, as Reborn's; a finished edit re-syncs a
                // registered device.
                TextField("Bark Push URL", text: Binding(
                    get: { settings.barkPushURL ?? "" },
                    set: { v in $settings.update { $0.barkPushURL = v.isEmpty ? nil : v } }
                ), prompt: Text("https://api.day.app/yourdevicekey"))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit { Task { await pushURLEdited() } }
                .apolloSearchRow("Bark Push URL")

                // Centered action rows, not disclosure/detail cells.
                actionRow("Test Connection", id: "notificationBackend.testConnection") { await testConnection() }
                    .apolloSearchRow("Test Connection")
                actionRow("Test Bark Notification", id: "notificationBackend.testBark") { await testBark() }
                    .apolloSearchRow("Test Bark Notification", lastBeforeFooter: true)
            } header: {
                Text("Notification Backend")
                    .apolloSectionHeader()
            } footer: {
                Text("Self-hosted only. Leave empty to disable. This build has no Apple push entitlement, so notifications arrive through the free Bark app: set Bark Delivery and its push URL (from the Bark app) before registering.")
                    .apolloSectionFooter()
            }

            Section {
                actionRow("Register Device", id: "notificationBackend.register") { await register() }
                    .apolloPlainSettingsRowInsets()
                actionRow("Send Test from Backend", id: "notificationBackend.backendTest") { await backendTest() }
                    .apolloPlainSettingsRowInsets()
                actionRow("Unregister Device", id: "notificationBackend.unregister", role: .destructive) { await unregister() }
                    .apolloPlainSettingsRowInsets(rule: false)
            } header: {
                Text("Registration")
                    .apolloSectionHeader()
            } footer: {
                Text("Registering sends this device's Bark push URL and your signed-in accounts' Reddit sign-in to your backend, which then checks your inbox and watchers and pushes new activity. Accounts signed in without an API key can't be watched by a backend.")
                    .apolloSectionFooter()
            }
        }
        .apolloSettingsSearchScroll()
        .apolloSettingsListAppearance()
        .navigationTitle("Notification Backend")
        .overlay { if busy { ProgressView().controlSize(.large) } }
        .alert("Notification Backend", isPresented: $alertMessage.isPresent()) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func actionRow(_ title: String, id: String, role: ButtonRole? = nil,
                           action: @escaping () async -> Void) -> some View {
        Button(title, role: role) {
            // Row geometry is applied by the caller (`apolloSearchRow` /
            // `apolloPlainSettingsRowInsets`).
            guard !busy else { return }
            busy = true
            Task {
                await action()
                busy = false
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .disabled(busy)
        .accessibilityIdentifier(id)
    }

    private func testConnection() async {
        guard let base = PushNotificationClient.backendURL(settings) else {
            alertMessage = "Backend URL is empty or invalid."
            return
        }
        alertMessage = await PushNotificationClient.testBackend(base).message
    }

    private func testBark() async {
        guard settings.barkEnabled else { alertMessage = "Turn on Bark Delivery first."; return }
        guard let url = PushNotificationClient.barkURL(settings) else {
            alertMessage = "No valid Bark push URL is set."
            return
        }
        let sound = notificationSettings.notificationSound.barkSoundID
        alertMessage = await PushNotificationClient.sendBark(PushNotificationClient.testMessage(sound: sound), to: url).message
    }

    private func register() async {
        guard let accountManager else { alertMessage = "No accounts to register."; return }
        let registrable = await accountManager.pushRegistrationAccounts()
        guard !registrable.isEmpty else {
            alertMessage = "None of your accounts is signed in with an API key, so a backend can't check them."
            return
        }
        let api = customAPISettings
        do {
            let count = try await PushNotificationClient.register(
                settings: settings, accounts: registrable,
                soundID: notificationSettings.notificationSound.barkSoundID,
                clientID: RedditOAuthConfig.clientID,
                clientSecret: RedditOAuthConfig.clientSecret,
                redirectURI: RedditOAuthConfig.redirectURI,
                userAgent: api.userAgent.flatMap { $0.isEmpty ? nil : $0 } ?? RedditAPIClient.oauthUserAgent)
            PushRegistrationState.markRegistered(settings)
            alertMessage = "Registered this device and \(count) account\(count == 1 ? "" : "s"). New inbox activity will arrive through Bark."
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func backendTest() async {
        do {
            try await PushNotificationClient.sendBackendTest(settings: settings)
            alertMessage = "The backend sent a test notification. It should arrive through Bark in a few seconds."
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    /// Reborn: turning Bark off removes the device from the backend, so it
    /// stops pushing to the old endpoint; turning it back on registers the
    /// device and its accounts again, if they were registered before.
    private func barkDeliveryChanged(_ on: Bool, wasRegistered: Bool) async {
        let suspendedKey = "com.pendo324.Phoebus.pushRegistrationSuspended"
        if on {
            guard UserDefaults.standard.bool(forKey: suspendedKey) else { return }
            UserDefaults.standard.removeObject(forKey: suspendedKey)
            guard settings.backendURL?.isEmpty == false, PushNotificationClient.barkURL(settings) != nil else { return }
            await register()
        } else if wasRegistered {
            try? await PushNotificationClient.unregister(settings: settings)
            PushRegistrationState.clear()
            UserDefaults.standard.set(true, forKey: suspendedKey)
        }
    }

    private func pushURLEdited() async {
        guard PushRegistrationState.hasRegistration, settings.barkEnabled,
              PushNotificationClient.barkURL(settings) != nil,
              settings.backendURL?.isEmpty == false else { return }
        if (try? await PushNotificationClient.syncDevice(
            settings: settings, soundID: notificationSettings.notificationSound.barkSoundID)) != nil {
            PushRegistrationState.markRegistered(settings)
        }
    }

    private func unregister() async {
        do {
            try await PushNotificationClient.unregister(settings: settings)
            PushRegistrationState.clear()
            alertMessage = "This device was removed from the backend. No more notifications will be sent to it."
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}
