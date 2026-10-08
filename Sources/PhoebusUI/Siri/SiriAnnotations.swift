import AppIntents
import Combine
import SwiftUI
import PhoebusCore

/// Reborn "Siri & Spotlight" (#1299): what is onscreen, for Siri's context
/// ("summarize this post", "send this reply to Sam"). The app target owns the
/// entity types and installs these once; until then, and while indexing is
/// off, rows carry no annotation.
public enum SiriAnnotationFactory {
    public nonisolated(unsafe) static var post: (@Sendable (String) -> EntityIdentifier)?
    public nonisolated(unsafe) static var comment: (@Sendable (String) -> EntityIdentifier)?
    /// Opening a post from the app's own UI is a meaningful action; the app
    /// donates it so Siri learns what this person reads. Apple: donate only
    /// UI-initiated actions, once per completed action, never per feed row.
    public nonisolated(unsafe) static var donateOpenPost: (@MainActor @Sendable (String) -> Void)?
}

public extension View {
    /// Annotates a feed row or a post header with its post entity.
    func siriPostContext(_ fullName: String) -> some View {
        modifier(SiriEntityAnnotation(id: SiriOnscreen.postID(fullName), make: SiriAnnotationFactory.post))
    }

    /// Annotates a comment row with its comment entity.
    func siriCommentContext(_ fullName: String) -> some View {
        modifier(SiriEntityAnnotation(id: SiriOnscreen.commentID(fullName), make: SiriAnnotationFactory.comment))
    }

    /// The post detail screen's single focus: its user activity carries the
    /// open post (Apple: a screen about one entity delivers it through
    /// NSUserActivity), and opening it is donated.
    func siriPostActivity(fullName: String, title: String) -> some View {
        modifier(SiriPostActivity(fullName: fullName, title: title))
    }
}

/// Re-reads whether an id may be annotated now, and again whenever the
/// content service says the set changed (hide, opt-out, account switch).
private struct SiriAllowed: ViewModifier {
    let id: String?
    @Binding var allowed: Bool

    func body(content: Content) -> some View {
        content
            .onAppear { allowed = id.map(SiriOnscreen.contains) ?? false }
            .onReceive(NotificationCenter.default.publisher(for: .phoebusSiriOnscreenChanged)
                .receive(on: DispatchQueue.main)) { _ in
                allowed = id.map(SiriOnscreen.contains) ?? false
            }
    }
}

private struct SiriEntityAnnotation: ViewModifier {
    let id: String?
    let make: (@Sendable (String) -> EntityIdentifier)?
    @State private var allowed = false

    func body(content: Content) -> some View {
        // Before iOS 27 nothing installs the factory: leave the row alone.
        if make == nil {
            content
        } else {
            annotated(content).modifier(SiriAllowed(id: id, allowed: $allowed))
        }
    }

    @ViewBuilder
    private func annotated(_ content: Content) -> some View {
        if #available(iOS 18.4, *) {
            content.appEntityIdentifier(allowed ? id.flatMap { make?($0) } : nil)
        } else {
            content
        }
    }
}

private struct SiriPostActivity: ViewModifier {
    let fullName: String
    let title: String
    @State private var allowed = false
    @State private var donated = false

    private var id: String? { SiriOnscreen.postID(fullName) }

    func body(content: Content) -> some View {
        if SiriAnnotationFactory.post == nil {
            content
        } else {
            activity(content)
        }
    }

    private func activity(_ content: Content) -> some View {
        content
            .userActivity("com.pendo324.Phoebus.viewPost", isActive: allowed) { activity in
                activity.title = title
                activity.isEligibleForSearch = false
                activity.isEligibleForHandoff = false
                if #available(iOS 18.2, *) {
                    activity.appEntityIdentifier = id.flatMap { SiriAnnotationFactory.post?($0) }
                }
            }
            .modifier(SiriAllowed(id: id, allowed: $allowed))
            .onChange(of: allowed) { _, isAllowed in
                guard isAllowed, !donated else { return }
                donated = true
                SiriAnnotationFactory.donateOpenPost?(fullName)
            }
    }
}
