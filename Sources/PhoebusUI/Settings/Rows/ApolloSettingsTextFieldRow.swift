import SwiftUI

/// Reborn's settings text-field cell: the caption on the left and a
/// right-aligned callout-size text field taking a fixed fraction of the
/// row (55% in the API-keys form, 60% in Translation), with a clear
/// button while editing and no autocorrect or capitalisation.
///
/// A bare `TextField("Label", …)` shows the label only as a placeholder,
/// so the caption would vanish once the field is filled.
public struct ApolloSettingsTextFieldRow: View {
    let label: String
    let placeholder: String
    let secure: Bool
    let widthFraction: CGFloat
    let keyboard: UIKeyboardType
    @Binding var text: String

    public init(_ label: String, placeholder: String? = nil, text: Binding<String>,
                secure: Bool = false, widthFraction: CGFloat = 0.55, keyboard: UIKeyboardType = .default) {
        self.label = label
        self.placeholder = placeholder ?? label
        self._text = text
        self.secure = secure
        self.widthFraction = widthFraction
        self.keyboard = keyboard
    }

    public var body: some View {
        GeometryReader { geo in
            HStack {
                Text(label)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Group {
                    if secure {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                    }
                }
                .font(.callout)
                .multilineTextAlignment(.trailing)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .accessibilityLabel(label)
                .frame(width: geo.size.width * widthFraction)
            }
            .frame(height: geo.size.height)
        }
        .frame(minHeight: 22)
    }
}
