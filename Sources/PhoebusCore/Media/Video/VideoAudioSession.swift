import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

/// Claims the audio session so an unmuted video is audible.
///
/// `AVAudioSession`'s default category follows the ring/silent switch and
/// loses to other audio, so `player.isMuted = false` alone is not enough:
/// the session is set to Playback before unmuting (Apollo defaults to
/// Ambient, which silences AVPlayer audio), then activated.
///
/// Everything else runs in `.ambient`, which mixes: a muted video must not
/// stop someone's music, and `.soloAmbient` or a leftover `.playback`
/// category does. Session calls block for a noticeable moment, so they run
/// on their own queue rather than the main thread.
public enum VideoAudioSession {
    #if canImport(AVFoundation) && !os(macOS)
    private static let queue = DispatchQueue(label: "com.pendo324.Phoebus.audioSession", qos: .userInitiated)
    #endif

    /// Pauses every playing video and returns what restarts them. A category
    /// switch or deactivation stops the session's running players and AVPlayer
    /// does not start again by itself. Set by the app; runs on the main thread.
    public nonisolated(unsafe) static var pausePlaying: () -> (@Sendable () -> Void) = { {} }

    /// The app's resting category; call once at launch.
    public static func configureAmbient() {
        #if canImport(AVFoundation) && !os(macOS)
        queue.async { try? AVAudioSession.sharedInstance().setCategory(.ambient) }
        #endif
    }

    /// Who holds the session, by a stable id per holder (a player view, the
    /// PiP card, the gallery viewer). A claim/release count drifts when a view
    /// claims on every unmute but releases only on a gated disappear, leaving
    /// someone's podcast paused. A holder claims at most once and releasing
    /// twice is harmless.
    private nonisolated(unsafe) static var owners: Set<String> = []
    private nonisolated(unsafe) static var isActive = false
    private static let lock = NSLock()

    /// Claims `.playback` for `owner`, which is what makes an unmuted
    /// video audible even with the ring/silent switch engaged; `.ambient`
    /// is precisely the category that silences it. Idempotent per owner.
    public static func claim(_ owner: String) {
        lock.lock()
        defer { lock.unlock() }
        owners.insert(owner)
        #if canImport(AVFoundation) && !os(macOS)
        // The category every time: another app can have changed it since.
        let activate = !isActive
        let resume = activate ? pausePlaying() : {}
        queue.async {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .moviePlayback)
            if activate { try? session.setActive(true) }
            DispatchQueue.main.async(execute: resume)
        }
        #endif
        isActive = true
    }

    /// `owner` is done with sound (muted, or gone). The last holder
    /// deactivates with `notifyOthersOnDeactivation`, so an interrupted
    /// app resumes rather than staying paused.
    public static func release(_ owner: String) {
        lock.lock()
        defer { lock.unlock() }
        guard owners.remove(owner) != nil, owners.isEmpty, isActive else { return }
        deactivate()
    }

    /// Drops every holder: a screen going away entirely must not leave
    /// the session active because some stale view never let go.
    public static func releaseAll() {
        lock.lock()
        defer { lock.unlock() }
        owners.removeAll()
        guard isActive else { return }
        deactivate()
    }

    private static func deactivate() {
        #if canImport(AVFoundation) && !os(macOS)
        let resume = pausePlaying()
        queue.async {
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(false, options: [.notifyOthersOnDeactivation])
            try? session.setCategory(.ambient)
            DispatchQueue.main.async(execute: resume)
        }
        #endif
        isActive = false
    }

    /// For another holder of the session (system PiP's mixable claim):
    /// runs on the same queue so its calls stay in order with these.
    #if canImport(AVFoundation) && !os(macOS)
    public static func perform(_ work: @escaping @Sendable (AVAudioSession) -> Void) {
        queue.async { work(AVAudioSession.sharedInstance()) }
    }
    #endif

    public static var holdsClaim: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isActive
    }

    /// Test hook.
    public static func holds(_ owner: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return owners.contains(owner)
    }

    public static func shouldClaim(isMuted: Bool) -> Bool { !isMuted }
}
