import SwiftUI
import PhoebusCore
#if canImport(AVFoundation) && canImport(UIKit)
@preconcurrency import AVFoundation
import UIKit
#endif

/// Scans a QR code encoding a `ThemeQRCodePayload` (the import half of Reborn's
/// theme QR flow) with `AVCaptureMetadataOutput`. Falls back to pasting the
/// payload when the camera is unavailable or denied.
public struct ThemeQRScanScreen: View {
    let onImported: (Theme) -> Void
    @State private var pastedPayload = ""
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    public init(onImported: @escaping (Theme) -> Void) {
        self.onImported = onImported
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                #if canImport(AVFoundation) && canImport(UIKit)
                QRScannerRepresentable { payload in
                    importPayload(payload)
                }
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                #endif

                Text("Or paste a theme code:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Theme code", text: $pastedPayload, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                Button("Import") {
                    importPayload(pastedPayload)
                }
                .disabled(pastedPayload.isEmpty)

                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
                Spacer()
            }
            .padding(.top)
            .navigationTitle("Import Theme")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func importPayload(_ payload: String) {
        do {
            let theme = try ThemeQRCodePayload.decode(payload)
            onImported(theme)
            dismiss()
        } catch {
            errorMessage = "That doesn't look like a valid theme code."
        }
    }
}

#if canImport(AVFoundation) && canImport(UIKit)
private struct QRScannerRepresentable: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.onScan = onScan
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

/// Minimal `AVCaptureSession` + `AVCaptureMetadataOutput` QR scanner.
/// Calls `onScan` once per distinct scanned string (debounced via
/// `lastScanned` so a QR code held in frame doesn't fire repeatedly).
final class QRScannerViewController: UIViewController, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var lastScanned: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            return
        }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let session = session
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        session.stopRunning()
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let value = object.stringValue,
              value != lastScanned else {
            return
        }
        lastScanned = value
        onScan?(value)
    }
}
#endif
