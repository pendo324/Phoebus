import Foundation

/// The QR-code payload for Apollo-Reborn's theme sharing: encodes a `Theme`
/// as compact JSON to render as a QR code (sharing) or decode after scanning
/// (importing). Pure Codable logic so the round-trip is testable without
/// camera or image-generation code, which lives in PhoebusUI (`ThemeQRCodeView`).
public enum ThemeQRCodePayload {
    public enum PayloadError: Error, Sendable {
        case invalidPayload
    }

    /// Encodes a theme as a compact JSON string suitable for a QR
    /// code's limited data capacity — drops `isGenerated` since an
    /// imported theme should always import as a fresh non-generated
    /// theme regardless of whether the sharer's copy was AI-generated.
    public static func encode(_ theme: Theme) throws -> String {
        struct SharedTheme: Codable {
            let name: String
            let accentColorHex: String
            let commentDepthColorHexes: [String]
            let isDark: Bool
        }
        let shared = SharedTheme(name: theme.name, accentColorHex: theme.accentColorHex, commentDepthColorHexes: theme.commentDepthColorHexes, isDark: theme.isDark)
        let data = try JSONEncoder().encode(shared)
        guard let string = String(data: data, encoding: .utf8) else { throw PayloadError.invalidPayload }
        return string
    }

    /// Decodes a scanned QR payload back into an importable `Theme`,
    /// assigning it a fresh unique ID (so importing the same shared
    /// theme twice, or a theme whose ID happens to collide with a
    /// built-in, doesn't silently overwrite anything).
    public static func decode(_ payload: String) throws -> Theme {
        struct SharedTheme: Codable {
            let name: String
            let accentColorHex: String
            let commentDepthColorHexes: [String]
            let isDark: Bool
        }
        guard let data = payload.data(using: .utf8),
              let shared = try? JSONDecoder().decode(SharedTheme.self, from: data),
              !shared.commentDepthColorHexes.isEmpty else {
            throw PayloadError.invalidPayload
        }
        let id = "imported_\(UUID().uuidString.prefix(8))"
        return Theme(id: id, name: shared.name, accentColorHex: shared.accentColorHex, commentDepthColorHexes: shared.commentDepthColorHexes, isDark: shared.isDark, isGenerated: true)
    }
}
