import SwiftUI
import PhoebusCore

/// Apollo's translator: `translate.google.com` in an in-app browser with
/// injected dark-mode CSS matching the theme, rather than a native translation UI.
public struct TranslatorScreen: View {
    let originalText: String

    public init(originalText: String) {
        self.originalText = originalText
    }

    public var body: some View {
        NavigationStack {
            Group {
                if let url = TranslatorURLBuilder.translateURL(for: originalText) {
                    InAppSafariView(url: url)
                        .ignoresSafeArea()
                } else {
                    Text("Nothing to translate").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Translate")
            .navigationBarTitleDisplayModeIfAvailable()
        }
    }
}

#if canImport(Translation)
import Translation
#endif

public extension View {
    /// The Translate action: Google in a web view or, with "Use Apple Translate
    /// Sheet" on, iOS's native sheet (`.translationPresentation`, iOS 17.4+). The
    /// system sheet may send text to Apple, so it is never described as private.
    @ViewBuilder
    func apolloTranslator(isPresented: Binding<Bool>, text: String) -> some View {
        #if canImport(Translation)
        if TranslationSettingsStore.load().useAppleTranslateSheet {
            if #available(iOS 17.4, *) {
                self.translationPresentation(isPresented: isPresented, text: text)
            } else {
                self.sheet(isPresented: isPresented) { TranslatorScreen(originalText: text) }
            }
        } else {
            self.sheet(isPresented: isPresented) { TranslatorScreen(originalText: text) }
        }
        #else
        self.sheet(isPresented: isPresented) { TranslatorScreen(originalText: text) }
        #endif
    }
}
