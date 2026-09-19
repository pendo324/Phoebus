import SwiftUI
import PhoebusCore
#if canImport(CoreImage)
import CoreImage.CIFilterBuiltins
#endif

/// Renders a scannable QR code for a `Theme`'s `ThemeQRCodePayload` (the sharing
/// half of Reborn's theme QR flow) using `CIFilter.qrCodeGenerator`. Without
/// CoreImage (non-Apple platforms) it shows the raw payload text instead.
public struct ThemeQRCodeView: View {
    let theme: Theme

    public init(theme: Theme) {
        self.theme = theme
    }

    public var body: some View {
        VStack(spacing: 16) {
            if let payload = try? ThemeQRCodePayload.encode(theme) {
                #if canImport(CoreImage) && canImport(UIKit)
                if let uiImage = Self.generateQRCode(from: payload) {
                    Image(uiImage: uiImage)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 240, height: 240)
                } else {
                    Text(payload).font(.caption).padding()
                }
                #else
                Text(payload).font(.caption).padding()
                #endif
                Text(theme.name).font(.headline)
            } else {
                Text("Couldn't encode this theme.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .navigationTitle("Share Theme")
    }

    #if canImport(CoreImage) && canImport(UIKit)
    static func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        guard let outputImage = filter.outputImage else { return nil }
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaled = outputImage.transformed(by: transform)
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
    #endif
}
