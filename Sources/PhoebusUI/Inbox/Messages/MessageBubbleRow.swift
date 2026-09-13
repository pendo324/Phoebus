import SwiftUI
import PhoebusCore

/// One message drawn as a MessageKit-style bubble.
///
/// Apollo renders every conversation this way: regular DMs, Reddit Chat and
/// modmail share one bubble layout. Geometry: 260pt text cap, 18pt corner
/// radius, 12/8 padding, and a 40pt spacer on the message's own side so a
/// conversation reads as two columns.
public struct MessageBubbleRow<Accessory: View>: View {
    /// Author label shown above INCOMING bubbles only, MessageKit's
    /// `*MessageTopLabelAlignment` pair omits it on outgoing ones.
    let author: String
    let body_: String
    let date: Date?
    /// Whether this message is the signed-in user's.
    let isFromSelf: Bool
    /// Drawn under the bubble, on the message's own side. Used for
    /// modmail's PRIVATE NOTE badge.
    let accessory: Accessory
    /// Tints the bubble away from the accent, for a message that is
    /// not a normal reply (a moderator's private note).
    let bubbleTint: Color?

    public init(
        author: String,
        body: String,
        date: Date?,
        isFromSelf: Bool,
        bubbleTint: Color? = nil,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.author = author
        self.body_ = body
        self.date = date
        self.isFromSelf = isFromSelf
        self.bubbleTint = bubbleTint
        self.accessory = accessory()
    }

    private var bubbleColor: Color {
        if let bubbleTint { return bubbleTint }
        return isFromSelf ? Color.apolloAccent : Color(.secondarySystemFill)
    }

    private var textColor: Color {
        // A tinted (note) bubble keeps primary text: the tint is a
        // pale wash, not a saturated fill, so white would vanish.
        bubbleTint != nil ? Color.primary : (isFromSelf ? Color.white : Color.primary)
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isFromSelf { Spacer(minLength: 40) }

            VStack(alignment: isFromSelf ? .trailing : .leading, spacing: 2) {
                if !isFromSelf {
                    Text(author)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                // Inline media honours the real "Inline Media in
                // Messages" toggle (`EnableChatMedia`), so a linked
                // image in a PM renders rather than staying a bare URL.
                InlineMediaBodyView(body_, context: .messages)
                    .font(.body)
                    .foregroundStyle(textColor)
                    // Width-capped so a long message wraps inside a
                    // bubble instead of becoming a full-width slab.
                    .frame(maxWidth: 260, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(bubbleColor)
                    )

                HStack(spacing: 6) {
                    if let date {
                        Text(date, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    accessory
                }
            }

            if !isFromSelf { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: isFromSelf ? .trailing : .leading)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .padding(.vertical, 1)
    }
}
