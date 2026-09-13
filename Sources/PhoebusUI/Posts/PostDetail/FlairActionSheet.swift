import SwiftUI
import PhoebusCore
import ImageIO

/// Apollo's flair picker presented as an action sheet, used for
/// changing a post's flair after submission and for "Set User Flair".
///
/// Structure: title "Flair", one row per option with the applied one
/// prefixed by "✓ ", a destructive "Remove Flair" row shown when a flair
/// is applied (or the user is a moderator), then Cancel.
public struct FlairActionSheet {
    /// Builds the row set for `apolloActionSheet`.
    public static func rows(
        options: [RedditFlairOption],
        currentFlairID: String?,
        isModerator: Bool,
        sprites: [String: FlairSpriteImage] = [:],
        onSelect: @escaping (RedditFlairOption) -> Void,
        onRemove: @escaping () -> Void
    ) -> [ApolloActionSheetRow] {
        // Titles and ordering come from the shared, smoke-tested
        // `FlairActionRows` builder in PhoebusCore.
        let model = FlairActionRows.build(
            options: options.map { (id: $0.flairTemplateID, text: $0.displayText) },
            currentFlairID: currentFlairID,
            isModerator: isModerator
        )
        var rows: [ApolloActionSheetRow] = []
        for (index, row) in model.enumerated() where !row.isDestructive {
            let option = options[index]
            let sprite = option.spriteClass.flatMap { sprites[$0] }
            rows.append(ApolloActionSheetRow(row.title, leading: sprite.map { AnyView($0) },
                                             accessibilityIdentifier: "flair.option.\(option.flairTemplateID)") {
                onSelect(option)
            })
        }
        if model.contains(where: \.isDestructive) {
            rows.append(ApolloActionSheetRow("Remove Flair", isDestructive: true, accessibilityIdentifier: "flair.remove") {
                onRemove()
            })
        }
        return rows
    }
}

/// Presents the flair action sheet, loading the subreddit's flair
/// options on demand.
public struct FlairActionModifier: ViewModifier {
    @Binding var isPresented: Bool
    let subreddit: String
    let repository: RedditRepository
    /// A post fullname changes that post's flair; a username sets that
    /// user's flair in the subreddit. Exactly one is expected.
    var linkFullname: String?
    var username: String?
    var currentFlairID: String?
    var isModerator: Bool = false
    var onChanged: () -> Void = {}

    @State private var options: [RedditFlairOption] = []
    @State private var sprites: [String: FlairSpriteImage] = [:]

    public func body(content: Content) -> some View {
        content
            .task(id: isPresented) {
                guard isPresented, options.isEmpty else { return }
                if let linkFullname {
                    options = (try? await repository.fetchFlairOptions(forLink: linkFullname, subreddit: subreddit)) ?? []
                } else if let username {
                    options = (try? await repository.fetchUserFlairOptions(subreddit: subreddit, username: username)) ?? []
                }
                // Names show at once; sprites follow once the sheet is in.
                sprites = await FlairSpriteImage.load(for: options, subreddit: subreddit, repository: repository)
            }
            .apolloActionSheet(
                isPresented: $isPresented,
                title: "Flair",
                rows: FlairActionSheet.rows(
                    options: options,
                    currentFlairID: currentFlairID,
                    isModerator: isModerator,
                    sprites: sprites,
                    onSelect: { option in
                        Task {
                            try? await repository.selectFlair(
                                subreddit: subreddit,
                                templateID: option.flairTemplateID,
                                linkFullname: linkFullname,
                                username: username,
                                text: option.text
                            )
                            onChanged()
                        }
                    },
                    onRemove: {
                        Task {
                            try? await repository.selectFlair(
                                subreddit: subreddit,
                                templateID: nil,
                                linkFullname: linkFullname,
                                username: username
                            )
                            onChanged()
                        }
                    }
                )
            )
    }
}

extension View {
    /// Attaches the flair action sheet.
    public func apolloFlairActionSheet(
        isPresented: Binding<Bool>,
        subreddit: String,
        repository: RedditRepository,
        linkFullname: String? = nil,
        username: String? = nil,
        currentFlairID: String? = nil,
        isModerator: Bool = false,
        onChanged: @escaping () -> Void = {}
    ) -> some View {
        modifier(FlairActionModifier(
            isPresented: isPresented,
            subreddit: subreddit,
            repository: repository,
            linkFullname: linkFullname,
            username: username,
            currentFlairID: currentFlairID,
            isModerator: isModerator,
            onChanged: onChanged
        ))
    }
}

/// A flair's picture cut from its subreddit's old-reddit sprite sheet
/// (Reborn #1215), drawn before the flair's name the way Reborn puts the
/// crop in front of the prettified class. 16pt, Apollo's flair-emoji size
/// (`CommentFlairPill`), and round when the stylesheet rounds it.
public struct FlairSpriteImage: View {
    let image: CGImage
    let isRound: Bool

    static let size: CGFloat = 16

    public var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: Self.size, height: Self.size)
            .clipShape(RoundedRectangle(cornerRadius: isRound ? Self.size / 2 : 0))
    }

    /// Crops every text-less CSS-class option's sprite. Only a selector
    /// that has such rows reads the stylesheet, and a stylesheet Reborn
    /// can't parse leaves the names alone.
    static func load(for options: [RedditFlairOption], subreddit: String,
                     repository: RedditRepository) async -> [String: FlairSpriteImage] {
        let classes = Set(options.compactMap(\.spriteClass))
        guard !classes.isEmpty,
              let regions = try? await repository.fetchFlairSprites(subreddit: subreddit),
              !regions.isEmpty else { return [:] }
        var sheets: [URL: CGImage] = [:]
        var result: [String: FlairSpriteImage] = [:]
        for cssClass in classes {
            guard let region = regions[cssClass] else { continue }
            if sheets[region.sheetURL] == nil {
                sheets[region.sheetURL] = await sheet(at: region.sheetURL)
            }
            guard let sheet = sheets[region.sheetURL] else { continue }
            let bounds = CGRect(x: 0, y: 0, width: sheet.width, height: sheet.height)
            // Out-of-sheet regions are skipped, as in Reborn's crop guard.
            guard region.rect.width > 0, region.rect.height > 0,
                  bounds.insetBy(dx: -1, dy: -1).contains(region.rect),
                  let crop = sheet.cropping(to: region.rect) else { continue }
            result[cssClass] = FlairSpriteImage(image: crop, isRound: region.isRound)
        }
        return result
    }

    private static func sheet(at url: URL) async -> CGImage? {
        guard let data = await MediaBytes.data(for: url), let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
