import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Apollo's "Goodbye" wallpaper collection.
///
/// 32 wallpapers as remote imgur URLs, each with an artist credit, with a
/// per-device album: iPhone, iPad, or Mac (36, adding four
/// ultrawide/vertical variants). Captions and URLs follow the original
/// list and order. Nothing is redistributed: the links point at the
/// artists' own hosting and are fetched at runtime.
public struct GoodbyeWallpaper: Sendable, Equatable, Identifiable {
    public var id: String { iPhoneURL }
    /// "<Name> by <Artist>".
    public var caption: String
    public var iPhoneURL: String
    public var iPadURL: String

    public init(caption: String, iPhoneURL: String, iPadURL: String) {
        self.caption = caption
        self.iPhoneURL = iPhoneURL
        self.iPadURL = iPadURL
    }

    /// The wallpaper's title, without the trailing artist credit.
    public var name: String {
        caption.components(separatedBy: " by ").first ?? caption
    }

    /// The artist, for the credit line.
    public var artist: String? {
        let parts = caption.components(separatedBy: " by ")
        return parts.count > 1 ? parts.dropFirst().joined(separator: " by ") : nil
    }

    /// The URL for the current device class.
    public var url: String {
        #if canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .pad ? iPadURL : iPhoneURL
        #else
        return iPhoneURL
        #endif
    }

    public static let all: [GoodbyeWallpaper] = [
        .init(caption: "Adventures by David Lanham", iPhoneURL: "https://i.imgur.com/8dY2Pp9.jpeg", iPadURL: "https://i.imgur.com/NgqQDXt.jpeg"),
        .init(caption: "Apollo A1 by Michael Flarup", iPhoneURL: "https://i.imgur.com/AJ7WTuw.jpeg", iPadURL: "https://i.imgur.com/xRgVIr5.jpeg"),
        .init(caption: "Apollo-san by Helunky", iPhoneURL: "https://i.imgur.com/ngR7qDL.jpeg", iPadURL: "https://i.imgur.com/IM7eaeT.jpeg"),
        .init(caption: "Apollopy by Matthew Skiles", iPhoneURL: "https://i.imgur.com/uM4Nhls.jpeg", iPadURL: "https://i.imgur.com/D4e8NRF.jpeg"),
        .init(caption: "Argyle by Basic Apple Guy", iPhoneURL: "https://i.imgur.com/n7W7z73.jpeg", iPadURL: "https://i.imgur.com/LGTFDZA.jpeg"),
        .init(caption: "Bean Paradise by Beanthew Skiles", iPhoneURL: "https://i.imgur.com/Wzyu5Gu.jpeg", iPadURL: "https://i.imgur.com/9chtljy.jpeg"),
        .init(caption: "Blast Off! by Helunky", iPhoneURL: "https://i.imgur.com/a0b1Aqm.jpeg", iPadURL: "https://i.imgur.com/uxL6lBI.jpeg"),
        .init(caption: "Stories Around the Campfire by Anthony Piraino (The Iconfactory)", iPhoneURL: "https://i.imgur.com/E36nGoy.jpeg", iPadURL: "https://i.imgur.com/nbXfwlv.jpeg"),
        .init(caption: "Playing Cards by Brad Ellis", iPhoneURL: "https://i.imgur.com/dIvbzUo.jpeg", iPadURL: "https://i.imgur.com/E1SJuDl.jpeg"),
        .init(caption: "Escaping the Circus by Matthew Skiles", iPhoneURL: "https://i.imgur.com/6DETaba.jpeg", iPadURL: "https://i.imgur.com/gfhQEON.jpeg"),
        .init(caption: "Dino Spoon by Zheng3 / Christian Selig", iPhoneURL: "https://i.imgur.com/A3klbfB.jpeg", iPadURL: "https://i.imgur.com/xPAlIbH.jpeg"),
        .init(caption: "Ducky Buddy by Lux", iPhoneURL: "https://i.imgur.com/bG6rLfV.jpeg", iPadURL: "https://i.imgur.com/RPWHHxh.jpeg"),
        .init(caption: "Floating by Lalit", iPhoneURL: "https://i.imgur.com/8uitIJZ.jpeg", iPadURL: "https://i.imgur.com/XThv2A3.jpeg"),
        .init(caption: "Hang Time by David Lanham", iPhoneURL: "https://i.imgur.com/HGtCU4m.jpeg", iPadURL: "https://i.imgur.com/YG60e02.jpeg"),
        .init(caption: "Harmony by David Lanham", iPhoneURL: "https://i.imgur.com/x41Gm6F.jpeg", iPadURL: "https://i.imgur.com/AuMVMXF.jpeg"),
        .init(caption: "Helping Hand by David Lanham", iPhoneURL: "https://i.imgur.com/PttkHAv.jpeg", iPadURL: "https://i.imgur.com/Eu8S2qN.jpeg"),
        .init(caption: "Icarus by Michael Flarup", iPhoneURL: "https://i.imgur.com/HHtNY2z.jpeg", iPadURL: "https://i.imgur.com/SUrzm6S.jpeg"),
        .init(caption: "Keep it Up by David Lanham", iPhoneURL: "https://i.imgur.com/TXH8bxS.jpeg", iPadURL: "https://i.imgur.com/od72XYW.jpeg"),
        .init(caption: "The Masked Bot by Michael Flarup", iPhoneURL: "https://i.imgur.com/Kc9o9G4.jpeg", iPadURL: "https://i.imgur.com/6AJi43x.jpeg"),
        .init(caption: "Mechapollo by Jorge Velez", iPhoneURL: "https://i.imgur.com/P2zN82M.jpeg", iPadURL: "https://i.imgur.com/Rm7kGfK.jpeg"),
        .init(caption: "Neon by Candbot & Matthew Skiles", iPhoneURL: "https://i.imgur.com/mGXS70i.jpeg", iPadURL: "https://i.imgur.com/4sD0stc.jpeg"),
        .init(caption: "Onwards by David Lanham", iPhoneURL: "https://i.imgur.com/tnHobJA.jpeg", iPadURL: "https://i.imgur.com/ztAWzn7.jpeg"),
        .init(caption: "Pixel Icons by Matthew Skiles", iPhoneURL: "https://i.imgur.com/zM0R57G.jpeg", iPadURL: "https://i.imgur.com/ndhknT2.jpeg"),
        .init(caption: "Reminiscing by David Lanham", iPhoneURL: "https://i.imgur.com/l0YLuEo.jpeg", iPadURL: "https://i.imgur.com/sLLw9hY.jpeg"),
        .init(caption: "Retirement Island by Matthew Skiles", iPhoneURL: "https://i.imgur.com/6cVawXf.jpeg", iPadURL: "https://i.imgur.com/DdGBYTZ.jpeg"),
        .init(caption: "Scanning Space by Gavin Nelson", iPhoneURL: "https://i.imgur.com/CmyLZNG.jpeg", iPadURL: "https://i.imgur.com/mUcqY2r.jpeg"),
        .init(caption: "Scenery by Yannick Lung", iPhoneURL: "https://i.imgur.com/dN9YnGc.jpeg", iPadURL: "https://i.imgur.com/55F1J2a.jpeg"),
        .init(caption: "Solara by gleptech", iPhoneURL: "https://i.imgur.com/HlsdbJg.jpeg", iPadURL: "https://i.imgur.com/5AH1P6E.jpeg"),
        .init(caption: "Spaceman by Matthew Skiles", iPhoneURL: "https://i.imgur.com/DDdkfh0.jpeg", iPadURL: "https://i.imgur.com/K4CY2P1.jpeg"),
        .init(caption: "Special Place by David Lanham", iPhoneURL: "https://i.imgur.com/cnzm9SA.jpeg", iPadURL: "https://i.imgur.com/eM90sR4.jpeg"),
        .init(caption: "Squingus by Adam Whitcroft", iPhoneURL: "https://i.imgur.com/RHGvhLK.jpeg", iPadURL: "https://i.imgur.com/SB6T3BR.jpeg"),
        .init(caption: "Sticker Bomb by Michael Flarup", iPhoneURL: "https://i.imgur.com/9EkRNQs.jpeg", iPadURL: "https://i.imgur.com/A4yOLxp.jpeg"),
    ]
}
