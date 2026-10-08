import SwiftUI
import PhoebusCore

/// Reborn "In-App Update Prompt" (#1343): once a day on foreground (when
/// Automatic Update Checks is on) the build's AltStore source is read, and a
/// newer build gets a sheet that hands off to the sideloader. Settings ›
/// About › Check for Updates always checks and reports the outcome. A build
/// without a release channel (a local or dev build) has nothing to check.
@MainActor
public final class AppUpdateCoordinator: ObservableObject {
    public static let shared = AppUpdateCoordinator()

    struct Prompt: Identifiable {
        let update: AppUpdate
        /// Offered for automatic prompts only: a manual check always shows the update.
        let offerSkip: Bool
        var id: Int { update.build }
    }

    struct Message: Equatable {
        let title: String
        let text: String
    }

    @Published var prompt: Prompt?
    @Published var message: Message?
    @Published private(set) var status: Status = .idle

    enum Status: Equatable {
        case idle, checking, upToDate
        case available(String)
    }

    /// The row detail: "Checking…", "1.4.0 (132) available", "Up to date", or nothing before a check.
    var statusText: String? {
        switch status {
        case .idle: nil
        case .checking: "Checking…"
        case .upToDate: "Up to date"
        case .available(let version): "\(version) available"
        }
    }

    private var available: AppUpdate?
    private var fetching = false
    /// A manual check is riding on the fetch in flight, so its outcome is shown.
    private var manualWaiting = false
    private var promptWaiting = false
    /// Bumped to cancel whichever prompt retry is waiting for a quiet moment.
    private var promptGeneration = 0
    private var promptedBuild: Int?

    private var installedBuild: Int? { AppUpdateChecker.installedBuild(infoDictionary: Bundle.main.infoDictionary) }

    private init() {}

    // MARK: Automatic

    /// Call on every foreground.
    public func checkIfNeeded() {
        guard AppUpdatePolicy.automaticChecks.load(),
              let channel = BuildChannel.current, let build = installedBuild else { return }
        guard AppUpdatePolicy.isDue(lastCheck: AppUpdatePolicy.lastCheck()) else {
            // A prompt that couldn't show earlier may be able to now.
            promptIfPossible()
            return
        }
        startFetch(channel: channel, installedBuild: build)
    }

    private func promptIfPossible() {
        guard let update = available, !promptWaiting, promptedBuild != update.build,
              !manualWaiting, AppUpdatePolicy.automaticChecks.load(),
              AppUpdatePolicy.shouldPrompt(for: update, skippedBuild: AppUpdatePolicy.skippedBuild()) else { return }
        promptWaiting = true
        let generation = promptGeneration
        Task { [weak self] in
            // Other launch UI may still be on screen; retry for a few seconds.
            for delay in [0.0, 1, 2, 4, 8] {
                if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                guard let self, generation == self.promptGeneration else { return }
                guard AppUpdatePolicy.automaticChecks.load() else {
                    self.promptWaiting = false
                    return
                }
                if self.prompt == nil, Self.isBaseUIOnly() {
                    self.promptWaiting = false
                    self.promptedBuild = update.build
                    self.prompt = Prompt(update: update, offerSkip: true)
                    return
                }
            }
            guard let self, generation == self.promptGeneration else { return }
            // Blocked every time: forget the check so the next foreground retries.
            self.promptWaiting = false
            AppUpdatePolicy.clearLastCheck()
        }
    }

    /// Stops a prompt retry still waiting (a newer result or a manual check supersedes it).
    private func cancelPendingPrompt() {
        promptGeneration += 1
        promptWaiting = false
    }

    // MARK: Manual

    /// Settings › About › Check for Updates.
    func checkNow() {
        guard let channel = BuildChannel.current, let build = installedBuild else {
            message = Message(title: "Can't Check for Updates",
                              text: "This build didn't come from a Phoebus release channel, so there is no update source to check.")
            return
        }
        cancelPendingPrompt()
        manualWaiting = true
        status = .checking
        startFetch(channel: channel, installedBuild: build)
    }

    // MARK: Fetch

    /// The only place the source is read: a check that starts while one is in
    /// flight shares it, so a manual check during an automatic one still
    /// shows its result.
    private func startFetch(channel: BuildChannel, installedBuild: Int) {
        guard !fetching else { return }
        fetching = true
        Task { [weak self] in
            let result = try? await AppUpdateChecker.check(channel: channel, installedBuild: installedBuild)
            self?.finishFetch(result)
        }
    }

    private func finishFetch(_ result: AppUpdateResult?) {
        fetching = false
        if let result {
            cancelPendingPrompt()
            AppUpdatePolicy.recordCheck()
            switch result {
            case .upToDate:
                available = nil
                status = .upToDate
            case .available(let update):
                available = update
                status = .available(update.versionText)
            }
        } else if manualWaiting {
            status = available.map { .available($0.versionText) } ?? .idle
        }
        guard manualWaiting else {
            // An automatic failure stays due, retried next foreground.
            if result != nil { promptIfPossible() }
            return
        }
        manualWaiting = false
        switch result {
        case nil:
            message = Message(title: "Couldn't Check for Updates", text: "Check your connection and try again.")
        case .available(let update)?:
            promptedBuild = update.build
            prompt = Prompt(update: update, offerSkip: false)
        case .upToDate?:
            message = Message(title: "You're Up to Date", text: "Phoebus \(Self.installedVersionText) is the latest version.")
        }
    }

    static var installedVersionText: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    // MARK: Presentation

    func skip(_ update: AppUpdate) {
        AppUpdatePolicy.skip(update)
    }

    /// Automatic prompts wait for nothing else to be modal (a share sheet,
    /// a composer, the lock screen).
    private static func isBaseUIOnly() -> Bool {
        #if canImport(UIKit)
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows.first(where: \.isKeyWindow) }.first
        return window?.rootViewController?.presentedViewController == nil
        #else
        return true
        #endif
    }
}

extension View {
    /// Hosts the update sheet and the manual check's alerts; once, at the app root.
    public func appUpdatePrompt() -> some View {
        modifier(AppUpdatePromptModifier())
    }
}

private struct AppUpdatePromptModifier: ViewModifier {
    @ObservedObject private var coordinator = AppUpdateCoordinator.shared

    func body(content: Content) -> some View {
        content
            .sheet(item: $coordinator.prompt) { prompt in
                AppUpdateSheet(prompt: prompt, coordinator: coordinator)
            }
            .alert(coordinator.message?.title ?? "",
                   isPresented: Binding(get: { coordinator.message != nil }, set: { if !$0 { coordinator.message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(coordinator.message?.text ?? "")
            }
    }
}

/// Settings › About › Update Installer: where the update sheet's Update
/// button goes. Phoebus's own; Reborn always asks.
struct UpdateInstallerRow: View {
    @Setting(AppUpdatePolicy.installer) private var installer

    var body: some View {
        ApolloSettingsPicker("Update Installer", selection: $installer.binding,
                             options: UpdateInstaller.allCases, display: { $0.title })
    }
}

/// Settings › About › Check for Updates, with the status as its detail.
struct CheckForUpdatesRow: View {
    @ObservedObject private var coordinator = AppUpdateCoordinator.shared

    var body: some View {
        Button {
            coordinator.checkNow()
        } label: {
            HStack {
                Text("Check for Updates")
                    .apolloFont(size: ApolloSettingsRowMetrics.titlePointSize)
                Spacer()
                if let status = coordinator.statusText {
                    Text(status)
                        .apolloFont(size: ApolloSettingsRowMetrics.titlePointSize)
                        .foregroundStyle(Color.apolloSettingsSecondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(coordinator.status == .checking)
        .accessibilityIdentifier("about.checkForUpdates")
    }
}
