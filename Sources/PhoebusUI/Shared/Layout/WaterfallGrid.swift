import SwiftUI
import PhoebusCore

/// A variable-height waterfall grid matching Reborn's Gallery View. Each
/// item is appended to the shortest column so tall and short cells
/// interleave.
public struct WaterfallGrid<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let columns: Int
    let spacing: CGFloat
    let aspectRatio: (Item) -> Double
    let content: (Item) -> Content

    public init(items: [Item], columns: Int = 2, spacing: CGFloat = 4, aspectRatio: @escaping (Item) -> Double, @ViewBuilder content: @escaping (Item) -> Content) {
        self.items = items
        self.columns = max(1, columns)
        self.spacing = spacing
        self.aspectRatio = aspectRatio
        self.content = content
    }

    public var body: some View {
        let buckets = distributeIntoColumns()
        HStack(alignment: .top, spacing: spacing) {
            ForEach(0..<columns, id: \.self) { columnIndex in
                LazyVStack(spacing: spacing) {
                    ForEach(buckets[columnIndex]) { item in
                        content(item)
                    }
                }
            }
        }
    }

    /// Greedy shortest-column-first bucketing. Cell heights depend on display
    /// width, so inverse aspect ratio stands in for height; it is stable across
    /// re-renders.
    private func distributeIntoColumns() -> [[Item]] {
        var buckets: [[Item]] = Array(repeating: [], count: columns)
        var heights = Array(repeating: 0.0, count: columns)
        for item in items {
            let ratio = aspectRatio(item)
            let relativeHeight = ratio > 0 ? 1.0 / ratio : 1.0
            let shortest = heights.indices.min(by: { heights[$0] < heights[$1] }) ?? 0
            buckets[shortest].append(item)
            heights[shortest] += relativeHeight
        }
        return buckets
    }
}
