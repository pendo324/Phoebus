import SwiftUI
import PhoebusCore

/// Apollo's "Text Faces" kaomoji picker sheet (`option-text-faces` in the Quick Bar
/// "More Actions" menu): browse and insert one of the 40 emoticons in `TextFaces.all`.
public struct TextFacesPickerScreen: View {
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    public init(onSelect: @escaping (String) -> Void) {
        self.onSelect = onSelect
    }

    public var body: some View {
        NavigationStack {
            List(TextFaces.all, id: \.self) { face in
                Button {
                    onSelect(face)
                    dismiss()
                } label: {
                    Text(face)
                        .font(.title3)
                        .foregroundStyle(.primary)
                }
            }
            .navigationTitle("Text Faces")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
