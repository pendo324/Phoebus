import Foundation
import PhoebusCore

// In-app update prompt (Reborn "In-App Update Prompt", #1343), against an
// AltStore source in the shape scripts/ci/update-altstore-source.py writes.
@MainActor func checkAppUpdatePrompt() async throws {
    let source = (try? Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/altstore-source-nightly-v2.json"))) ?? Data()
    check("update fixture loads", !source.isEmpty)

    let behind = AppUpdateChecker.parse(source, channel: .nightly, installedBuild: 120)
    guard case .available(let update)? = behind else {
        check("an older build is offered the newest one", false)
        return
    }
    check("the newest build is offered, whatever the list order", update.build == 132)
    check("the update carries its version", update.version == "1.4.0" && update.versionText == "1.4.0 (132)")
    check("the update carries the entry's notes", update.notes == "feat(updates): offer new versions in the app")
    check("the update carries its date", update.date == ISO8601DateFormatter().date(from: "2026-10-07T18:30:05+00:00"))
    check("the update carries its download URL",
          update.downloadURL?.absoluteString == "https://github.com/pendo324/Phoebus/releases/download/nightly/Phoebus-v1.4.0-abc1234.ipa")
    check("another app's newer build is ignored", update.build != 999)
    check("the source is the build's channel's", update.sourceURL == AppUpdateSource.sourceURL(for: .nightly))
    check("the nightly source URL", AppUpdateSource.sourceURL(for: .nightly).absoluteString == "https://pendo324.github.io/AltStoreRepo/nightly/source.json")
    check("the stable source URL", AppUpdateSource.sourceURL(for: .stable).absoluteString == "https://pendo324.github.io/AltStoreRepo/source.json")

    check("the newest installed build is up to date", AppUpdateChecker.parse(source, channel: .nightly, installedBuild: 132) == .upToDate)
    check("a build newer than the source is up to date", AppUpdateChecker.parse(source, channel: .nightly, installedBuild: 500) == .upToDate)
    check("a build one behind is offered", AppUpdateChecker.parse(source, channel: .nightly, installedBuild: 131) != .upToDate)
    check("builds compare as numbers, not text", AppUpdateChecker.parse(source, channel: .nightly, installedBuild: 99) != .upToDate)

    check("a source without Phoebus is unusable",
          AppUpdateChecker.parse(Data(#"{"apps":[{"bundleIdentifier":"com.example.other","versions":[]}]}"#.utf8), channel: .stable, installedBuild: 1) == nil)
    check("a source without apps is unusable", AppUpdateChecker.parse(Data("{}".utf8), channel: .stable, installedBuild: 1) == nil)
    check("a body that is not JSON is unusable", AppUpdateChecker.parse(Data("<html>".utf8), channel: .stable, installedBuild: 1) == nil)
    check("entries without a build number are skipped",
          AppUpdateChecker.parse(Data(#"{"apps":[{"bundleIdentifier":"com.pendo324.Phoebus","versions":[{"version":"2.0.0"}]}]}"#.utf8), channel: .stable, installedBuild: 1) == nil)

    let legacy = Data(#"""
    {"apps":[{"bundleIdentifier":"com.pendo324.Phoebus","version":"2.0.0","buildVersion":"7",
    "versionDate":"2026-10-07T18:30:05+00:00","versionDescription":"Release notes: https://github.com/pendo324/Phoebus/releases/tag/v2.0.0.",
    "downloadURL":"http://insecure.example/Phoebus.ipa"}]}
    """#.utf8)
    guard case .available(let flat)? = AppUpdateChecker.parse(legacy, channel: .stable, installedBuild: 6) else {
        check("the flat fields of an older source are read", false)
        return
    }
    check("the flat fields of an older source are read", flat.version == "2.0.0" && flat.build == 7)
    check("a non-https download is dropped", flat.downloadURL == nil)
    check("a stable release's notes link is found, without the full stop",
          flat.notesURL?.absoluteString == "https://github.com/pendo324/Phoebus/releases/tag/v2.0.0")
    check("a commit subject has no notes link", update.notesURL == nil)

    check("the installed build reads from Info.plist", AppUpdateChecker.installedBuild(infoDictionary: ["CFBundleVersion": "42"]) == 42)
    check("an unnumbered build is not read", AppUpdateChecker.installedBuild(infoDictionary: ["CFBundleVersion": "1.2"]) == nil)
    check("no Info.plist, no build", AppUpdateChecker.installedBuild(infoDictionary: nil) == nil)

    let altStore = UpdateSideloader.altStore.handoffURL(for: update)?.absoluteString
    check("AltStore adds the channel's source",
          altStore?.hasPrefix("altstore-classic://source?url=https") == true && altStore?.contains("nightly/source.json") == true)
    check("SideStore adds the channel's source",
          UpdateSideloader.sideStore.handoffURL(for: update)?.absoluteString.hasPrefix("sidestore://source?url=https") == true)
    check("Feather installs the IPA",
          UpdateSideloader.feather.handoffURL(for: update)?.absoluteString == "feather://install/" + update.downloadURL!.absoluteString)
    check("FlareStore downloads the IPA",
          UpdateSideloader.flareStore.handoffURL(for: update)?.absoluteString == "flarestore://downloadApp=" + update.downloadURL!.absoluteString)
    check("Feather adds the source when there is no IPA",
          UpdateSideloader.feather.handoffURL(for: flat)?.absoluteString == "feather://source/https://pendo324.github.io/AltStoreRepo/source.json")

    check("Ask Every Time is the default installer", AppUpdatePolicy.installer.defaultValue == .askEveryTime)
    check("the installer setting is Phoebus's own key", AppUpdatePolicy.installer.key == "Phoebus.updateInstaller")
    check("the installer choices are Ask Every Time, the four sideloaders and the IPA",
          UpdateInstaller.allCases.map(\.title) == ["Ask Every Time", "AltStore", "SideStore", "Feather", "FlareStore", "Download IPA"])
    for installer in [UpdateInstaller.altStore, .sideStore, .feather, .flareStore] {
        check("\(installer.title) hands off to its sideloader's link",
              installer.handoffURL(for: update) == installer.sideloader?.handoffURL(for: update))
        check("\(installer.title) is opened directly",
              UpdateHandoff.plan(installer: installer, for: update) == .open(installer, installer.sideloader!.handoffURL(for: update)!))
    }
    check("Download IPA opens the IPA", UpdateHandoff.plan(installer: .downloadIPA, for: update) == .open(.downloadIPA, update.downloadURL!))
    check("Ask Every Time shows the chooser", UpdateHandoff.plan(installer: .askEveryTime, for: update) == .chooser)
    check("Download IPA with no IPA shows the chooser", UpdateHandoff.plan(installer: .downloadIPA, for: flat) == .chooser)
    check("the chooser offers every installer that can take the update",
          UpdateInstaller.choices(for: update) == [.altStore, .sideStore, .feather, .flareStore, .downloadIPA])
    check("the chooser drops the IPA when the source has none",
          UpdateInstaller.choices(for: flat) == [.altStore, .sideStore, .feather, .flareStore])
    let installerDefaults = UserDefaults(suiteName: "phoebus.smoke.updateInstaller")!
    installerDefaults.removePersistentDomain(forName: "phoebus.smoke.updateInstaller")
    check("no installer is chosen at first", AppUpdatePolicy.installer.load(from: installerDefaults) == .askEveryTime)
    AppUpdatePolicy.installer.save(.sideStore, to: installerDefaults)
    check("a chosen installer reads back", AppUpdatePolicy.installer.load(from: installerDefaults) == .sideStore)
    installerDefaults.set(Data(#""someFutureInstaller""#.utf8), forKey: AppUpdatePolicy.installer.key)
    check("an unknown installer reads as Ask Every Time", AppUpdatePolicy.installer.load(from: installerDefaults) == .askEveryTime)
    installerDefaults.removePersistentDomain(forName: "phoebus.smoke.updateInstaller")

    let now = Date(timeIntervalSince1970: 1_800_000_000)
    check("a build never checked is due", AppUpdatePolicy.isDue(lastCheck: nil, now: now))
    check("a check an hour ago is not due", !AppUpdatePolicy.isDue(lastCheck: now.addingTimeInterval(-3600), now: now))
    check("a check just under a day ago is not due", !AppUpdatePolicy.isDue(lastCheck: now.addingTimeInterval(-86_399), now: now))
    check("a check a day ago is due", AppUpdatePolicy.isDue(lastCheck: now.addingTimeInterval(-86_400), now: now))
    check("a check in the future is due", AppUpdatePolicy.isDue(lastCheck: now.addingTimeInterval(3600), now: now))

    check("an unskipped update is prompted", AppUpdatePolicy.shouldPrompt(for: update, skippedBuild: nil))
    check("a skipped build is not prompted", !AppUpdatePolicy.shouldPrompt(for: update, skippedBuild: "132"))
    check("a newer build than the skipped one is prompted", AppUpdatePolicy.shouldPrompt(for: update, skippedBuild: "131"))

    let defaults = UserDefaults(suiteName: "phoebus.smoke.updates")!
    defaults.removePersistentDomain(forName: "phoebus.smoke.updates")
    check("no check is recorded at first", AppUpdatePolicy.lastCheck(in: defaults) == nil)
    AppUpdatePolicy.recordCheck(at: now, in: defaults)
    check("a recorded check reads back", AppUpdatePolicy.lastCheck(in: defaults) == now)
    defaults.set("not a date", forKey: "UpdateLastCheck")
    check("a restored non-date check reads as never", AppUpdatePolicy.lastCheck(in: defaults) == nil)
    AppUpdatePolicy.recordCheck(at: now, in: defaults)
    AppUpdatePolicy.clearLastCheck(in: defaults)
    check("a cleared check is due again", AppUpdatePolicy.lastCheck(in: defaults) == nil)
    check("nothing is skipped at first", AppUpdatePolicy.skippedBuild(in: defaults) == nil)
    AppUpdatePolicy.skip(update, in: defaults)
    check("skipping records the build", AppUpdatePolicy.skippedBuild(in: defaults) == "132")
    defaults.removePersistentDomain(forName: "phoebus.smoke.updates")

    check("automatic update checks are on by default", AppUpdatePolicy.automaticChecks.load())
    check("automatic update checks use Reborn's key", AppUpdatePolicy.automaticChecks.key == "AutomaticUpdateChecks")
}
