import Foundation

/// The result wording of Apollo-Reborn's "Save All Media" batch (#1048),
/// kept pure so the smoke test can pin it verbatim.
public enum SaveAllMediaSummary {
    /// Upstream's one menu title for every collection.
    public static let menuTitle = "Save All Media"
    /// The menu symbol.
    public static let menuSymbol = "square.and.arrow.down.on.square"

    public enum Style: Sendable, Equatable { case success, info, error }

    public struct Result: Sendable, Equatable {
        public var title: String
        public var detail: String?
        public var style: Style

        public init(title: String, detail: String?, style: Style) {
            self.title = title
            self.detail = detail
            self.style = style
        }
    }

    /// "Saved!" / "Saved All N Items!" when everything landed,
    /// otherwise "Saved X of N Items" with a cancelled/failed detail.
    public static func result(total: Int, saved: Int, failed: Int, cancelled: Bool) -> Result {
        let skipped = max(0, total - saved - failed)
        let allSaved = saved == total
        let title = allSaved
            ? (total == 1 ? "Saved!" : "Saved All \(total) Items!")
            : "Saved \(saved) of \(total) Items"
        var detail: String?
        if cancelled && skipped > 0 {
            detail = failed > 0 ? "Cancelled · \(failed) failed · \(skipped) skipped" : "Cancelled · \(skipped) skipped"
        } else if failed > 0 {
            detail = "\(failed) could not be saved to Photos."
        }
        let style: Style = allSaved ? .success : (failed > 0 ? .error : .info)
        return Result(title: title, detail: detail, style: style)
    }

    /// The progress panel's counter.
    public static func counter(completed: Int, total: Int) -> String {
        "\(min(completed, total)) / \(total)"
    }
}
