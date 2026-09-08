import Foundation

/// Builds the translator URL: Apollo embeds `https://translate.google.com/?text=<encoded>`
/// in an in-app browser. Pure URL logic so it is testable on Linux, separate
/// from the presentation in PhoebusUI's TranslatorScreen.
public enum TranslatorURLBuilder {
    public static func translateURL(for text: String) -> URL? {
        guard !text.isEmpty else { return nil }
        var components = URLComponents(string: "https://translate.google.com/")
        components?.queryItems = [URLQueryItem(name: "text", value: text)]
        return components?.url
    }
}
