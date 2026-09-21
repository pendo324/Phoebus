import SwiftUI
import PhoebusCore

/// The detent slider Apollo AI's settings use for Minimum Post Length and the
/// two detail rows.
///
/// - A 17pt title on the left with a right-aligned value in monospaced
///   digits at 15pt, so "150 words" does not jiggle.
/// - A tick label strip beneath the slider, 10pt in tertiary colour,
///   distributed equally.
/// - The row dims to 0.45 alpha when disabled and is 94pt tall.
/// - Tapping a tick label selects that stop.
///
/// While dragging it applies hysteresis: it moves to the next stop only once
/// the finger passes 0.65 of the way. SwiftUI's `step:` snaps at the midpoint
/// (0.5), which flickers between two stops.
struct ApolloAIDetentSlider: View {
    let label: String
    let valueText: String
    let tickLabels: [String]
    @Binding var selectedIndex: Int

    @Environment(\.isEnabled) private var isEnabled

    /// All three slider rows are 94pt.
    static let rowHeight: CGFloat = 94
    /// Matches Apollo AI's hysteretic index.
    static let hysteresis: Float = 0.65

    /// Continuous position while dragging, so the thumb tracks the
    /// finger between stops instead of jumping.
    @State private var raw: Float?

    private var maxIndex: Int { max(0, tickLabels.count - 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 17))
                Spacer(minLength: 8)
                Text(valueText)
                    // Monospaced digits: the value label uses a 15pt monospaced-digit font.
                    .font(.system(size: 15).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { Double(raw ?? Float(selectedIndex)) },
                    set: { newValue in
                        raw = Float(newValue)
                        let next = Self.hystereticIndex(
                            raw: Float(newValue), current: selectedIndex,
                            minimum: 0, maximum: maxIndex)
                        if next != selectedIndex { selectedIndex = next }
                    }),
                in: 0...Double(maxIndex)
            ) { editing in
                // Settle onto the chosen stop when the drag ends.
                if !editing { raw = nil }
            }
            .accessibilityLabel(label)
            .accessibilityValue(valueText)

            HStack(spacing: 0) {
                ForEach(Array(tickLabels.enumerated()), id: \.offset) { index, tick in
                    Text(tick)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        // Tapping a tick selects it; the label strip is part of the hit area.
                        .onTapGesture {
                            guard isEnabled else { return }
                            selectedIndex = index
                        }
                }
            }
        }
        .frame(height: Self.rowHeight - 16)
        // 0.45 disabled alpha, not SwiftUI's own dimming.
        .opacity(isEnabled ? 1 : 0.45)
    }

    /// Hysteretic index selection.
    ///
    /// Delegates to `ApolloAIDetentSliderMath` so the Linux smoke suite can
    /// exercise it; this view itself needs SwiftUI.
    ///
    /// Walks one stop at a time rather than rounding, so the index moves by at
    /// most one per update and the 0.65 threshold is measured from the current
    /// stop.
    static func hystereticIndex(raw: Float, current: Int,
                                minimum: Int, maximum: Int) -> Int {
        ApolloAIDetentSliderMath.hystereticIndex(
            raw: raw, current: current, minimum: minimum, maximum: maximum)
    }
}
