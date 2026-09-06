import Foundation

/// An image's real format, read from its first bytes. A photo picked from
/// the library is often HEIC, so uploads can't just be labelled `image/jpeg`.
public enum ImageFileType: Equatable, Sendable {
    case jpeg, png, gif, webp, heic

    public init(sniffing data: Data) {
        let bytes = [UInt8](data.prefix(12))
        func starts(_ prefix: [UInt8], at offset: Int = 0) -> Bool {
            bytes.count >= offset + prefix.count && Array(bytes[offset..<offset + prefix.count]) == prefix
        }
        if starts([0x89, 0x50, 0x4E, 0x47]) { self = .png }
        else if starts([0x47, 0x49, 0x46]) { self = .gif }
        else if starts(Array("RIFF".utf8)) && starts(Array("WEBP".utf8), at: 8) { self = .webp }
        else if starts(Array("ftyp".utf8), at: 4),
                let brand = String(bytes: bytes.dropFirst(8), encoding: .ascii),
                ["heic", "heix", "hevc", "heim", "heis", "mif1", "msf1"].contains(brand) { self = .heic }
        else { self = .jpeg }
    }

    public var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        case .gif: return "gif"
        case .webp: return "webp"
        case .heic: return "heic"
        }
    }

    public var mimeType: String {
        switch self {
        case .jpeg: return "image/jpeg"
        case .png: return "image/png"
        case .gif: return "image/gif"
        case .webp: return "image/webp"
        case .heic: return "image/heic"
        }
    }

    /// Formats Reddit's uploads accept as they are; anything else is
    /// re-encoded as JPEG first.
    public var isWebSafe: Bool { self == .jpeg || self == .png || self == .gif }
}
