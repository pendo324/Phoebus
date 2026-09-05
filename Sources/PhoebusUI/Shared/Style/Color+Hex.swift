import SwiftUI
import PhoebusCore
#if canImport(UIKit)
import UIKit
#endif

/// Shared hex-string Color parsing, used by `Theme` and any feature
/// storing a color. Accepts a bare 6-digit RGB hex string (no leading
/// `#`), matching how `Theme.accentColorHex` is stored.
public extension Color {
    init(hex: String) {
        // Unparseable input draws black.
        let value = ThemeColorMath.parseHex(hex) ?? 0
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }

    /// Reverse of `init(hex:)`: a bare 6-digit uppercase RGB hex string
    /// with no leading `#`.
    var hexString: String {
        #if canImport(UIKit)
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
        #else
        return "000000"
        #endif
    }
}
