import Foundation
import PhoebusCore

// Hold menus on inline comment images/GIFs and on post-header media
// (`Apollo-Reborn#1400`, `#1435`).
@MainActor func checkMediaHoldMenus() async throws {
    typealias M = MediaHoldMenu
    func menu(_ subject: M.Subject) -> [M.Action] { M.items(for: subject).map(\.action) }
    func enabled(_ subject: M.Subject) -> [M.Action] { M.items(for: subject).filter(\.isEnabled).map(\.action) }
    func image(_ string: String, album: Int = 1, failed: Bool = false) -> M.Subject {
        M.Subject(kind: .image, mediaURL: URL(string: string)!, albumCount: album, loadFailed: failed)
    }
    func gif(_ string: String, album: Int = 1, failed: Bool = false) -> M.Subject {
        M.Subject(kind: .gif, mediaURL: URL(string: string)!, albumCount: album, loadFailed: failed)
    }
    func video(_ string: String, link: String? = nil) -> M.Subject {
        M.Subject(kind: .video, mediaURL: URL(string: string)!, linkURL: link.flatMap { URL(string: $0) })
    }

    check("an image offers Copy Image, Save Image and Share",
          menu(image("https://i.redd.it/abc.jpeg")) == [.copyImage, .saveImage, .share])
    check("an album image adds Save All Media before Share, in Reborn's order",
          menu(image("https://i.redd.it/abc.jpeg", album: 3)) == [.copyImage, .saveImage, .saveAllMedia, .share])
    check("a GIF reads Copy GIF and Save GIF",
          menu(gif("https://i.imgur.com/abc.gif")) == [.copyGIF, .saveGIF, .share])
    check("an Imgur .gifv is an MP4 page, so it copies as a link rather than GIF bytes",
          menu(gif("https://i.imgur.com/abc.gifv")) == [.copyLink, .saveGIF, .share])
    check("a Reddit .gif served as format=mp4 copies as a link too",
          menu(gif("https://preview.redd.it/abc.gif?format=mp4&s=1")) == [.copyLink, .saveGIF, .share])
    check("a GIF file extension is read case-insensitively", M.hasGIFFile(URL(string: "https://media.giphy.com/media/x/giphy.GIF")!))

    check("a video offers Copy Link, Save Video and Share",
          menu(video("https://v.redd.it/abc/DASH_720.mp4")) == [.copyLink, .saveVideo, .share])
    check("a video never offers Copy Image",
          !menu(video("https://v.redd.it/abc/DASH_720.mp4")).contains(.copyImage)
          && !menu(video("https://cdn.example.com/x.mp4")).contains(.copyGIF))

    check("an image that failed to load keeps only the link-style actions",
          enabled(image("https://i.redd.it/abc.jpeg", failed: true)) == [.share])
    check("a failed album image also disables Save All Media",
          enabled(image("https://i.redd.it/abc.jpeg", album: 4, failed: true)) == [.share])
    check("a failed GIF disables its copy and save",
          enabled(gif("https://i.redd.it/abc.gif", failed: true)) == [.share])
    check("a failed .gifv still copies its link",
          enabled(gif("https://i.imgur.com/abc.gifv", failed: true)) == [.copyLink, .share])

    check("Save Video is available for a progressive MP4 or MOV on any host",
          M.canSaveVideo(URL(string: "https://thumbs.redgifs.com/Some-Clip.mp4")!)
          && M.canSaveVideo(URL(string: "https://streamable.com/x/video.MOV")!))
    check("Save Video is available for every v.redd.it shape the app plays or downloads",
          M.canSaveVideo(URL(string: "https://v.redd.it/abc123/HLSPlaylist.m3u8")!)
          && M.canSaveVideo(URL(string: "https://v.redd.it/abc123/DASHPlaylist.mpd")!)
          && M.canSaveVideo(URL(string: "https://v.redd.it/abc123/DASH_720.mp4")!)
          && M.canSaveVideo(URL(string: "https://v.redd.it/abc123.mp4")!))
    check("Save Video is greyed out for another host's HLS manifest",
          enabled(video("https://example.com/live/index.m3u8")) == [.copyLink, .share]
          && menu(video("https://example.com/live/index.m3u8")) == [.copyLink, .saveVideo, .share])
    check("Save Video is greyed out for WebM, which Photos does not take", !M.canSaveVideo(URL(string: "https://example.com/clip.webm")!))

    check("a v.redd.it stream's link is the short v.redd.it/<id> form people paste",
          M.shareableLink(for: URL(string: "https://v.redd.it/abc123/HLSPlaylist.m3u8")!).absoluteString == "https://v.redd.it/abc123"
          && M.shareableLink(for: URL(string: "https://v.redd.it/abc123/DASH_720.mp4")!).absoluteString == "https://v.redd.it/abc123")
    check("another host's video links to its own URL",
          M.shareableLink(for: URL(string: "https://example.com/clip.mp4")!).absoluteString == "https://example.com/clip.mp4")
    check("a video's Share and Copy Link use the page link when the host has one",
          video("https://thumbs.redgifs.com/Some-Clip.mp4", link: "https://www.redgifs.com/watch/someclip").shareURL.absoluteString
              == "https://www.redgifs.com/watch/someclip"
          && video("https://v.redd.it/abc123/HLSPlaylist.m3u8").shareURL.absoluteString == "https://v.redd.it/abc123")
    check("a RedGIFs id links to its watch page in lower case",
          M.redGifsPage(id: "SomeClip")?.absoluteString == "https://www.redgifs.com/watch/someclip")
    check("a Streamable id links to its page", M.streamablePage(id: "ab12")?.absoluteString == "https://streamable.com/ab12")

    check("every action has a title and a symbol",
          [M.Action.copyImage, .copyGIF, .copyLink, .saveImage, .saveGIF, .saveVideo, .saveAllMedia, .share]
              .allSatisfy { !$0.title.isEmpty && !$0.symbol.isEmpty })
    check("the titles are Reborn's",
          M.Action.copyImage.title == "Copy Image" && M.Action.copyGIF.title == "Copy GIF"
          && M.Action.saveImage.title == "Save Image" && M.Action.saveGIF.title == "Save GIF"
          && M.Action.saveVideo.title == "Save Video" && M.Action.copyLink.title == "Copy Link"
          && M.Action.saveAllMedia.title == "Save All Media" && M.Action.share.title == "Share")
}
