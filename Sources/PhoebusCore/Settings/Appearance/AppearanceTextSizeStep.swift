import Foundation

/// Step-count math mapping the Appearance "Text Size" slider
/// (`AppearanceSettings.textSizeScale`) onto SwiftUI's discrete
/// `DynamicTypeSize` scale. SwiftUI-free so the Linux `PhoebusCoreSmokeTest` can
/// run it; `PhoebusUI`'s `AppearanceTextSizeOverride` applies the step count.
///
/// Apollo's slider has seven stops, Extra Small through XXX Large
/// (`ApolloCustomTextSize` 1...7, 4 = Large, the default). Each stop is 0.1 of
/// `textSizeScale`, so they land on `.xSmall` ... `.xxxLarge`, pivoting on `.large`.
public enum AppearanceTextSizeStep {
    /// The slider's stops, in `ApolloCustomTextSize` order.
    public static let sizes: [Double] = [0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3]

    /// The scale for a stored `ApolloCustomTextSize` (one-based).
    public static func scale(forApolloTextSize raw: Int) -> Double? {
        sizes.indices.contains(raw - 1) ? sizes[raw - 1] : nil
    }

    /// Signed step count away from the pivot case (`.large`), clamped by the
    /// caller to the cases that exist on either side.
    public static func steps(forScale scale: Double) -> Int {
        Int(((scale - 1.0) / 0.1).rounded())
    }
}
