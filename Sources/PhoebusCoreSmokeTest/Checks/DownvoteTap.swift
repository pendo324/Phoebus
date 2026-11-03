import Foundation
import PhoebusCore

// --- Add Downvote Tap (Reborn ThreeStateVoting) ---

@MainActor func checkDownvoteTap() async throws {
    // Off (the default): a tap upvotes, or removes an upvote; a downvoted score is upvoted.
    check("Add Downvote Tap is off by default", !InfoRowSettings.default.downvoteTap)
    check("off: a tap on an unvoted score upvotes", ScoreTapVote.direction(current: nil, downvoteTap: false) == 1)
    check("off: a tap on an upvoted score removes the vote", ScoreTapVote.direction(current: true, downvoteTap: false) == 0)
    check("off: a tap on a downvoted score upvotes", ScoreTapVote.direction(current: false, downvoteTap: false) == 1)

    // On: none, up, down, none.
    check("on: a tap on an unvoted score upvotes", ScoreTapVote.direction(current: nil, downvoteTap: true) == 1)
    check("on: a tap on an upvoted score downvotes", ScoreTapVote.direction(current: true, downvoteTap: true) == -1)
    check("on: a tap on a downvoted score removes the vote", ScoreTapVote.direction(current: false, downvoteTap: true) == 0)

    // Three taps from nothing come back to nothing; the vote each direction leaves is what the next tap reads.
    func state(after direction: Int) -> Bool? { direction == 1 ? true : (direction == -1 ? false : nil) }
    var current: Bool?
    var seen: [Int] = []
    for _ in 0..<4 {
        let direction = ScoreTapVote.direction(current: current, downvoteTap: true)
        seen.append(direction)
        current = state(after: direction)
    }
    check("on: four taps send up, down, none, up", seen == [1, -1, 0, 1])

    // The setting: stored, defaulting off for settings saved before it existed.
    var info = InfoRowSettings.default
    info.downvoteTap = true
    let encoded = try JSONEncoder().encode(info)
    let roundTripped = try JSONDecoder().decode(InfoRowSettings.self, from: encoded)
    check("Add Downvote Tap survives a save and load", roundTripped.downvoteTap)
    let old = try JSONDecoder().decode(InfoRowSettings.self, from: Data(#"{"tapToUpvote":false}"#.utf8))
    check("Info Row settings saved before it existed decode with it off", !old.downvoteTap && !old.tapToUpvote)
    check("the Info Row summary says when it is on", info.summaryText.contains("Downvote tap on")
          && !InfoRowSettings.default.summaryText.contains("Downvote"))

    // Backups: Reborn's key is imported.
    let info0 = InfoRowSettingsStore.load()
    defer { InfoRowSettingsStore.save(info0) }
    InfoRowSettingsStore.save(.default)
    let imported = ApolloSettingsMigration.apply(.init(preferences: ["ThreeStateVoting": true]))
    check("a backup with ThreeStateVoting on turns Add Downvote Tap on",
          InfoRowSettingsStore.load().downvoteTap && imported.applied.contains("Add Downvote Tap"))
    _ = ApolloSettingsMigration.apply(.init(preferences: ["ThreeStateVoting": false]))
    check("a backup with ThreeStateVoting off turns it off", !InfoRowSettingsStore.load().downvoteTap)
    var on = InfoRowSettings.default
    on.downvoteTap = true
    InfoRowSettingsStore.save(on)
    let older = ApolloSettingsMigration.apply(.init(preferences: ["DefaultPostsSort": "hot"]))
    check("a backup without the key leaves it alone",
          InfoRowSettingsStore.load().downvoteTap && !older.applied.contains("Add Downvote Tap"))
    _ = ApolloSettingsMigration.apply(.init(preferences: ["ThreeStateVoting": 1]))
    check("a non-boolean ThreeStateVoting is ignored", InfoRowSettingsStore.load().downvoteTap)
    check("ThreeStateVoting is no longer a skipped key", ApolloSettingsMigration.notImported["ThreeStateVoting"] == nil)
}
