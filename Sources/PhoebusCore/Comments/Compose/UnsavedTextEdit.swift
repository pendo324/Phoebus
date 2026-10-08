import Foundation

/// Whether text being edited differs from what was last saved, for the
/// "Discard Changes?" prompt before an edit is thrown away. Compared the way
/// Reddit stores text: line endings as `\n`, edges trimmed.
public enum UnsavedTextEdit {
    public static func hasChanges(original: String, edited: String) -> Bool {
        normalized(original) != normalized(edited)
    }

    private static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
