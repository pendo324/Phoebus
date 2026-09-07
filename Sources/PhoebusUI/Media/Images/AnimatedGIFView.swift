import SwiftUI
import PhoebusCore
#if canImport(UIKit)
import AnimatedImage
#endif

/// Animated GIF playback via AnimatedImage's SwiftUI `AnimatedImagePlayer`
/// (ImageIO-backed, off-main-thread decode), replacing `CachedAsyncImage`'s
/// first-frame rendering for GIF media. Falls back to the static first frame
/// on plain macOS, where AnimatedImage's AppKit layer is a stub.
///
/// Reborn "Preferred GIF Fallback Format": when a GIF has a same-name `.mp4`
/// sibling (Reddit's CDN transcodes hosted GIFs to both), the smaller MP4
/// plays unless the user picks "GIF".
public struct AnimatedGIFView: View {
    @Setting(GeneralSettings.self) private var generalSettings
    let url: URL
    /// Reddit's own MP4 transcode of this GIF (`preview.images[0]
    /// .variants.mp4`), when the caller has the post.
    var redditMP4URL: URL?
    @State private var data: Data?
    #if canImport(UIKit)
    /// Built once when the bytes arrive, not in every `body`.
    @State private var animated: AnimatedImage?
    #endif
    @State private var failed = false
    /// Set once the user taps a non-autoplaying GIF to start it.
    @State private var isPlaying = false
    /// Whether the guessed `.mp4` sibling exists; `nil` until checked.
    @State private var siblingExists: Bool?

    public init(url: URL, redditMP4URL: URL? = nil) {
        self.url = url
        self.redditMP4URL = redditMP4URL
    }

    /// The real-CDN `.mp4` sibling of a `.gif`/`.gifv` URL, or `nil` if
    /// the URL doesn't end in a swappable GIF extension. Only actually
    /// used when `GeneralSettings.preferredGIFFallbackFormat == .mp4`.
    /// Shared with `GIFSaveService`'s save-format branching via
    /// `GIFURLHelpers` so both stay in sync.
    private var mp4FallbackURL: URL? {
        GIFURLHelpers.mp4SiblingURL(for: url)
    }

    /// A GIF played as MP4 opens fullscreen like any other video.
    @State private var showingFullscreen = false

    /// The MP4 to play: Reddit's own transcode first, else the guessed sibling
    /// once known to exist. `i.redd.it` serves no `.mp4` beside its GIFs, so the
    /// guess is checked before it's trusted.
    private var playableMP4URL: URL? {
        if let redditMP4URL { return redditMP4URL }
        return siblingExists == true ? mp4FallbackURL : nil
    }

    public var body: some View {
        if generalSettings.preferredGIFFallbackFormat == .mp4,
           redditMP4URL != nil || mp4FallbackURL != nil {
            if let mp4URL = playableMP4URL {
                MutedVideoPlayerView(url: mp4URL,
                                     onRequestFullscreen: { showingFullscreen = true })
                    .apolloMediaPager(items: [.video(mp4URL)], isPresented: $showingFullscreen,
                                      // The PLAYER owns the taps.
                                      attachesTapGestures: false)
            } else if siblingExists == false {
                gifBody
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .task(id: url) { await checkSibling() }
            }
        } else {
            gifBody
        }
    }

    private func checkSibling() async {
        guard let sibling = mp4FallbackURL else { siblingExists = false; return }
        siblingExists = await GIFMP4SiblingProbe.exists(sibling)
    }

    @ViewBuilder
    private var gifBody: some View {
        #if canImport(UIKit)
        Group {
            if data != nil, let animated {
                // Real "Autoplay GIFs/Videos" setting (Always / Wi-Fi
                // Only / Never). When autoplay is suppressed, the
                // GIF's first frame is shown with a play affordance and
                // a tap starts it - the media is never simply withheld.
                if isPlaying || AutoplayPolicy.shouldAutoplay() {
                    AnimatedImagePlayer(image: animated, contentMode: .fit)
                } else {
                    CachedAsyncImage(url: url)
                        .overlay {
                            Image(systemName: "play.circle.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.white.opacity(0.9))
                                .shadow(radius: 4)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { isPlaying = true }
                        .accessibilityIdentifier("gif.tapToPlay")
                }
            } else if failed {
                Image(systemName: "photo").foregroundStyle(.secondary)
            } else {
                ProgressView().task { await load() }
            }
        }
        #else
        CachedAsyncImage(url: url)
        #endif
    }

    private func load() async {
        guard let bytes = await MediaBytes.data(for: url) else {
            if !Task.isCancelled { failed = true }
            return
        }
        #if canImport(UIKit)
        animated = AnimatedImage(gif: bytes, withConfiguration: .fullQuality)
        #endif
        data = bytes
    }
}

/// Remembers which guessed `.mp4` siblings exist, checked with a HEAD.
actor GIFMP4SiblingProbe {
    static let shared = GIFMP4SiblingProbe()
    private var known: [URL: Bool] = [:]

    static func exists(_ url: URL) async -> Bool { await shared.check(url) }

    private func check(_ url: URL) async -> Bool {
        if let answer = known[url] { return answer }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 8
        let response = (try? await URLSession.shared.data(for: request))?.1 as? HTTPURLResponse
        // A missing file can come back as a placeholder image (Imgur
        // redirects to removed.png), so an image type is a "no" too.
        let answer = response.map { (200..<300).contains($0.statusCode) } == true
            && !(response?.mimeType ?? "").hasPrefix("image/")
        known[url] = answer
        return answer
    }
}

extension AnimatedImage.Configuration {
    /// The package's `.default` caps a GIF at 128pt and 1 MB of frames, which
    /// draws long GIFs as coarse blocks. This leaves room for a typical Reddit
    /// GIF at its own size, dropping frames beyond it.
    static var fullQuality: Self {
        Self(maxMemoryUsage: .init(value: 96, unit: .megabytes),
             maxSize: Size(width: 2048, height: 2048),
             maxLevelOfIntegrity: 1,
             interpolationQuality: .high)
    }
}
