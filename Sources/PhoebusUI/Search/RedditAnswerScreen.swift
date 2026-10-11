#if canImport(UIKit)
import SwiftUI
import UIKit
import PhoebusCore

/// The Search tab's Reddit Answers mode (Phoebus-only): the question, a live
/// "thinking" line while the reply streams, then the answer drawn natively,
/// its sources, follow-up questions and how many questions are left. Citation
/// chips and source rows open the cited post or comment in the app.
struct RedditAnswerScreen: View {
    let query: String
    let repository: RedditRepository
    let onOpen: (RedditURLTarget) -> Void
    /// Owned by the search screen, so a rebuilt answer screen keeps it.
    @ObservedObject var session: RedditAnswersSession
    /// A follow-up: asked as a new question.
    let onAsk: (String) -> Void

    @State private var showsSignIn = false
    @State private var copied = false
    @Environment(\.openURL) private var openURL

    private static let citationScheme = "phebus-answer"

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            // Each top-level block is its own scroll target, so the position
            // can be kept to the block (`session.scrollAnchor`).
            VStack(alignment: .leading, spacing: 12) {
                header.padding(.bottom, 6).id("header")
                if showsThinking { thinkingRow.id("thinking") }
                if session.content.hasAnswer {
                    ForEach(Array(session.content.blocks.enumerated()), id: \.offset) { index, block in
                        AnswerBlocksView(blocks: [block], content: session.content, sources: session.sources,
                                         citationURL: Self.citationURL, onOpen: onOpen)
                            .id("block-\(index)")
                    }
                }
                if case .failed(let error) = session.phase { failure(error).padding(.top, 6).id("failure") }
                if session.phase == .finished { finished }
            }
            .scrollTargetLayout()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .scrollPosition(id: $session.scrollAnchor, anchor: .top)
        .onDisappear { session.savedAnchor = session.scrollAnchor }
        .onAppear {
            guard let anchor = session.savedAnchor else { return }
            session.savedAnchor = nil
            // After the rebuilt scroll view has laid out its content.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(60))
                proxy.scrollTo(anchor, anchor: .top)
            }
        }
        }
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == Self.citationScheme {
                if let number = Int(url.lastPathComponent),
                   let citation = session.content.citations.first(where: { $0.number == number }) {
                    open(citation)
                }
                return .handled
            }
            openURL(url)
            return .handled
        })
        .task(id: query) { session.askIfNew(query, repository: repository) }
        .sheet(isPresented: $showsSignIn) {
            RedditAnswersSignInSheet { session.ask(query, repository: repository) }
        }
    }

    // MARK: Header and progress

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Reddit Answers", systemImage: "sparkles")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.apolloAccent)
            Text(query)
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var showsThinking: Bool {
        session.phase == .streaming && (!session.content.hasAnswer || session.content.isThinking)
    }

    private var thinkingRow: some View {
        let title = session.content.thinkingTitle ?? "Thinking\u{2026}"
        return HStack(spacing: 10) {
            ProgressView()
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reddit Answers: \(title)")
        .accessibilityIdentifier("answers.thinking")
    }

    private func failure(_ error: RedditAnswersError) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(error.errorDescription ?? "Something went wrong.", systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                if error.needsSignIn {
                    Button("Sign In") { showsSignIn = true }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("answers.signIn")
                }
                if case .quotaExhausted = error {} else {
                    Button("Try Again") { session.ask(query, repository: repository) }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("answers.retry")
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: After the answer

    @ViewBuilder
    private var finished: some View {
        // Direct children of the answer's stack, each its own scroll target.
        let content = session.content
        if content.hasAnswer { actions(content).padding(.vertical, 6).id("actions") }
        AnswerSourcesView(content: content, sources: session.sources, onOpen: onOpen, open: open)
        if !content.followUps.isEmpty { followUps(content.followUps).padding(.top, 6).id("followUps") }
        if let quota = session.quota { quotaLine(quota).id("quota") }
    }

    private func actions(_ content: RedditAnswerContent) -> some View {
        HStack(spacing: 10) {
            Button {
                UIPasteboard.general.string = content.plainText
                copied = true
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    copied = false
                }
            } label: {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .accessibilityIdentifier("answers.copy")
            ShareLink(item: content.plainText) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("answers.share")
            Spacer()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func followUps(_ questions: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AnswerSectionHeader("Ask a Follow-Up")
            ForEach(questions, id: \.self) { question in
                Button {
                    onAsk(question)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.turn.down.right")
                            .foregroundStyle(Color.apolloAccent)
                        Text(question)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ask: \(question)")
                .accessibilityIdentifier("answers.followUp")
            }
        }
    }

    private func quotaLine(_ quota: RedditAnswerQuota) -> some View {
        let text = quota.remaining <= 5
            ? "\(quota.summary) \u{00B7} resets in \(quota.resetDescription)"
            : quota.summary
        return Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("answers.quota")
    }

    // MARK: Opening

    static func citationURL(_ citation: AnswerCitation) -> URL {
        URL(string: "\(citationScheme)://citation/\(citation.number)")!
    }

    /// A cited post or comment: its own link when the answer had one, else what
    /// Reddit says it is.
    private func open(_ citation: AnswerCitation) {
        if let link = citation.permalink {
            let target = RedditURLTarget.parse(link)
            if case .unknown = target {} else { onOpen(target); return }
        }
        if let info = session.sources[citation.id] {
            onOpen(info.target)
        } else if citation.kind == .post {
            onOpen(.post(subreddit: citation.subreddit.map(AnswerNames.subredditName) ?? "", id: String(citation.id.dropFirst(3))))
        }
    }
}

// MARK: - Answer body

enum AnswerNames {
    /// "r/name" → "name".
    static func subredditName(_ prefixed: String) -> String {
        prefixed.hasPrefix("r/") ? String(prefixed.dropFirst(2)) : prefixed
    }
}

private struct AnswerSectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The answer's blocks. Lists and quotes nest, so this view draws itself.
private struct AnswerBlocksView: View {
    let blocks: [AnswerBlock]
    let content: RedditAnswerContent
    let sources: [String: RedditAnswerSourceInfo]
    let citationURL: (AnswerCitation) -> URL
    let onOpen: (RedditURLTarget) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
    }

    @ViewBuilder
    private func view(for block: AnswerBlock) -> some View {
        switch block {
        case .paragraph(let inlines):
            Text(AnswerText.attributed(inlines, font: .body, citationURL: citationURL))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        case .heading(let level, let inlines):
            Text(AnswerText.attributed(inlines, font: Self.headingFont(level), citationURL: citationURL))
                .padding(.top, 6)
                .accessibilityAddTraits(.isHeader)
        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ordered ? "\(index + 1)." : "\u{2022}")
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 18, alignment: .trailing)
                        AnswerBlocksView(blocks: item, content: content, sources: sources, citationURL: citationURL, onOpen: onOpen)
                    }
                }
            }
        case .quote(let inner):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5).fill(Color.secondary.opacity(0.5)).frame(width: 3)
                AnswerBlocksView(blocks: inner, content: content, sources: sources, citationURL: citationURL, onOpen: onOpen)
                    .foregroundStyle(.secondary)
            }
        case .code(let text):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.system(.footnote, design: .monospaced))
                    .padding(10)
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12)))
        case .rule:
            Divider()
        case .subreddits(let ids):
            AnswerChipFlow(spacing: 8) {
                ForEach(ids, id: \.self) { id in
                    if let name = subredditName(id) {
                        AnswerChip(title: "r/\(name)", systemImage: "person.2") { onOpen(.subreddit(name)) }
                    }
                }
            }
        case .references(let label, let references):
            VStack(alignment: .leading, spacing: 8) {
                if let label { AnswerSectionHeader(label) }
                ForEach(references, id: \.id) { reference in
                    AnswerSourceRow(id: reference.id, number: nil, info: sources[reference.id],
                                    fallback: reference.id.hasPrefix("t1_") ? "Comment" : "Post", onOpen: onOpen)
                }
            }
        }
    }

    private func subredditName(_ id: String) -> String? {
        if let named = content.consultedSubreddits.first(where: { $0.id == id })?.name {
            return AnswerNames.subredditName(named)
        }
        return sources[id]?.subreddit
    }

    private static func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2.weight(.bold)
        case 2: return .title3.weight(.bold)
        default: return .headline
        }
    }
}

/// The inlines as styled text: formatting runs, links, and the citation chips.
private enum AnswerText {
    static func attributed(_ inlines: [AnswerInline], font base: Font, citationURL: (AnswerCitation) -> URL) -> AttributedString {
        var result = AttributedString()
        for inline in inlines {
            switch inline {
            case .text(let text, let style):
                var run = AttributedString(text)
                var font = base
                if style.contains(.bold) { font = font.bold() }
                if style.contains(.italic) || style.contains(.quoted) { font = font.italic() }
                if style.contains(.code) {
                    font = .system(.callout, design: .monospaced)
                    run.backgroundColor = Color.secondary.opacity(0.15)
                }
                if style.contains(.superscript) {
                    font = .caption
                    run.baselineOffset = 6
                }
                run.font = font
                if style.contains(.strikethrough) { run.strikethroughStyle = .single }
                if style.contains(.quoted) { run.foregroundColor = .secondary }
                result += run
            case .link(let text, let url):
                var run = AttributedString(text)
                run.font = base
                if let url { run.link = url }
                result += run
            case .citation(let citation):
                var chip = AttributedString("\u{2009}\(citation.number)\u{2009}")
                chip.font = .caption2.weight(.semibold)
                chip.foregroundColor = Color.apolloAccent
                chip.backgroundColor = Color.apolloAccent.opacity(0.15)
                chip.baselineOffset = 3
                chip.link = citationURL(citation)
                result += AttributedString("\u{200A}") + chip
            case .lineBreak:
                result += AttributedString("\n")
            }
        }
        return result
    }
}

// MARK: - Sources

/// Cited posts and comments, other posts Reddit read, and the communities.
private struct AnswerSourcesView: View {
    let content: RedditAnswerContent
    let sources: [String: RedditAnswerSourceInfo]
    let onOpen: (RedditURLTarget) -> Void
    let open: (AnswerCitation) -> Void

    private var uncitedPosts: [String] {
        let cited = Set(content.citations.map(\.id))
        return content.consultedPostIDs.filter { !cited.contains($0) }.prefix(10).map { $0 }
    }

    private var showsCommunities: Bool {
        !content.consultedSubreddits.isEmpty && !content.blocks.contains { if case .subreddits = $0 { return true } else { return false } }
    }

    var body: some View {
        // Rows are the answer stack's own children (not wrapped), so each is a
        // scroll target and a return from a source lands back on its row.
        if !content.citations.isEmpty || !uncitedPosts.isEmpty {
            AnswerSectionHeader("Sources").padding(.top, 6).id("sources")
            ForEach(content.citations) { citation in
                AnswerSourceRow(id: citation.id, number: citation.number, info: sources[citation.id],
                                fallback: (citation.kind == .comment ? "Comment" : "Post")
                                    + (citation.subreddit.map { " in \($0)" } ?? ""),
                                onOpen: onOpen, openOverride: { open(citation) })
                    .id("source-\(citation.id)")
            }
            ForEach(uncitedPosts, id: \.self) { id in
                AnswerSourceRow(id: id, number: nil, info: sources[id], fallback: "Post", onOpen: onOpen)
                    .id("source-\(id)")
            }
        }
        if showsCommunities {
            VStack(alignment: .leading, spacing: 8) {
                AnswerSectionHeader("Communities")
                AnswerChipFlow(spacing: 8) {
                    ForEach(content.consultedSubreddits, id: \.id) { subreddit in
                        let name = subreddit.name.map(AnswerNames.subredditName) ?? sources[subreddit.id]?.subreddit
                        if let name {
                            AnswerChip(title: "r/\(name)", systemImage: "person.2") { onOpen(.subreddit(name)) }
                        }
                    }
                }
            }
            .padding(.top, 6)
            .id("communities")
        }
    }
}

private struct AnswerSourceRow: View {
    let id: String
    let number: Int?
    let info: RedditAnswerSourceInfo?
    let fallback: String
    let onOpen: (RedditURLTarget) -> Void
    var openOverride: (() -> Void)?

    var body: some View {
        Button {
            if let openOverride { openOverride() } else if let info { onOpen(info.target) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                if let number {
                    Text("\(number)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.apolloAccent)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.apolloAccent.opacity(0.15)))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(caption)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(info?.title ?? fallback)
                        .font(info?.kind == .comment ? .subheadline : .subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(info?.kind == .comment ? 3 : 2)
                        .multilineTextAlignment(.leading)
                    if let stats {
                        Text(stats).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.1)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens it in Phoebus.")
        .accessibilityIdentifier("answers.source")
    }

    private var caption: String {
        guard let info else { return number.map { "Source \($0)" } ?? "Source" }
        var parts: [String] = []
        if info.kind == .comment { parts.append("Comment") }
        if let subreddit = info.subreddit { parts.append("r/\(subreddit)") }
        if let author = info.author { parts.append("u/\(author)") }
        return parts.joined(separator: " \u{00B7} ")
    }

    private var stats: String? {
        guard let info else { return nil }
        var parts: [String] = []
        if let score = info.score { parts.append("\(GoogleSearchRedditInfo.compactCount(score)) points") }
        if info.kind == .post, let count = info.commentCount { parts.append("\(GoogleSearchRedditInfo.compactCount(count)) comments") }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    private var accessibilityText: String {
        let prefix = number.map { "Source \($0): " } ?? ""
        return prefix + [caption, info?.title ?? fallback].joined(separator: ", ")
    }
}

// MARK: - Chips

private struct AnswerChip: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("answers.community")
    }
}

/// Chips laid out left to right, wrapping to new lines.
private struct AnswerChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        arrange(in: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let arranged = arrange(in: bounds.width, subviews: subviews)
        for (subview, origin) in zip(subviews, arranged.origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(in width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}
#endif
