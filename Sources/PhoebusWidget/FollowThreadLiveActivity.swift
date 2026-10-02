import WidgetKit
import SwiftUI
import PhoebusCore
#if canImport(ActivityKit)
import ActivityKit
#endif

#if canImport(ActivityKit)
/// The lock-screen / Dynamic Island presentation of Apollo's Follow Thread Live
/// Activity. It lives in the widget extension, the only place iOS renders one,
/// and shares `FollowThreadActivity` with the app through PhoebusCore.
///
/// Shows the thread's comment count and score (`FollowThreadActivityState`) and
/// when they were last refreshed, rather than implying they are live: the push
/// half of this feature cannot work (see `FollowThreadActivity`).
@available(iOS 16.2, *)
struct FollowThreadLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FollowThreadActivity.self) { context in
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("r/\(context.attributes.subreddit)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(context.attributes.title)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(2)
                    Text("Updated \(context.state.updatedAt, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                VStack(spacing: 6) {
                    Label("\(context.state.commentCount)",
                          systemImage: "bubble.left.and.bubble.right")
                    Label("\(context.state.score)", systemImage: "arrow.up")
                }
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.6))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("\(context.state.commentCount)",
                          systemImage: "bubble.left.and.bubble.right")
                        .font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Label("\(context.state.score)", systemImage: "arrow.up")
                        .font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.title)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(2)
                }
            } compactLeading: {
                Image(systemName: "bubble.left.and.bubble.right")
            } compactTrailing: {
                Text("\(context.state.commentCount)")
            } minimal: {
                Image(systemName: "bubble.left.and.bubble.right")
            }
        }
    }
}
#endif
