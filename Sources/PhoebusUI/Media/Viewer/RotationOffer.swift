import SwiftUI
import PhoebusCore
#if canImport(CoreMotion) && canImport(UIKit)
import CoreMotion
import UIKit

/// Apollo's Portrait Lock Buddy: while iOS's rotation lock holds the app in
/// portrait, turning the phone sideways in the media viewer offers "Tap to
/// Rotate Image" along the screen's edge; tapping turns the media to match
/// the phone, and turning back offers "Tap to Rotate Back".
@MainActor
final class RotationOffer: ObservableObject {
    /// Which way the phone is held, read from gravity.
    enum Hold: Equatable {
        case portrait
        /// Right edge down: the media turns counterclockwise.
        case rightDown
        /// Left edge down: the media turns clockwise.
        case leftDown

        var angle: Angle {
            switch self {
            case .portrait: return .zero
            case .rightDown: return .degrees(-90)
            case .leftDown: return .degrees(90)
            }
        }
    }

    @Published private(set) var physical: Hold = .portrait
    /// How the media is currently turned.
    @Published var applied: Hold = .portrait
    @Published private(set) var showingOffer = false

    private let motion = CMMotionManager()
    private var hideTask: Task<Void, Never>?

    func start() {
        guard PortraitLockStore.load().portraitLockBuddy, motion.isDeviceMotionAvailable,
              !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 0.2
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let gravity = data?.gravity else { return }
            MainActor.assumeIsolated { self.read(gravity) }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        hideTask?.cancel()
    }

    private func read(_ gravity: CMAcceleration) {
        // Only while the app itself stayed portrait: an unlocked phone
        // rotates the viewer on its own.
        let scenePortrait = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.effectiveGeometry.interfaceOrientation }
            .first?.isPortrait ?? true
        let hold: Hold
        if !scenePortrait || abs(gravity.z) > 0.8 {
            hold = physical
        } else if gravity.x > 0.7 {
            hold = .rightDown
        } else if gravity.x < -0.7 {
            hold = .leftDown
        } else if gravity.y < -0.7 {
            hold = .portrait
        } else {
            hold = physical
        }
        guard hold != physical else { return }
        physical = hold
        let offer = hold != applied
        withAnimation(.easeInOut(duration: 0.2)) { showingOffer = offer }
        hideTask?.cancel()
        guard offer else { return }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) { self?.showingOffer = false }
        }
    }

    func accept() {
        hideTask?.cancel()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            applied = physical
            showingOffer = false
        }
        Haptics.light()
    }
}

/// The offer itself: a blurred pill on the screen edge that is up for
/// the turned phone, its text running along that edge.
struct RotationOfferButton: View {
    @ObservedObject var offer: RotationOffer
    let kind: String

    var body: some View {
        GeometryReader { geo in
            if offer.showingOffer {
                let back = offer.physical == .portrait
                let angle = back ? .zero : offer.physical.angle
                Button(action: offer.accept) {
                    HStack(spacing: 8) {
                        Image(systemName: back ? "rotate.left" : "rectangle.landscape.rotate")
                            .font(.system(size: 17, weight: .semibold))
                        Text(back ? "Tap to Rotate Back" : "Tap to Rotate \(kind)")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(.ultraThinMaterial, in: Capsule())
                    .environment(\.colorScheme, .dark)
                }
                .buttonStyle(.plain)
                .fixedSize()
                .rotationEffect(angle)
                .position(position(for: offer.physical, in: geo.size))
                .transition(.opacity)
                .accessibilityIdentifier("mediaPager.rotationOffer")
            }
        }
    }

    /// Against the edge that is on top for the turned phone, or at the
    /// bottom when offering to turn back.
    private func position(for hold: RotationOffer.Hold, in size: CGSize) -> CGPoint {
        switch hold {
        case .rightDown: return CGPoint(x: 40, y: size.height / 2)
        case .leftDown: return CGPoint(x: size.width - 40, y: size.height / 2)
        case .portrait: return CGPoint(x: size.width / 2, y: size.height - 140)
        }
    }
}

extension View {
    /// Turns the media to `hold`, swapping width and height so it fills
    /// the turned screen.
    func rotatedForHold(_ hold: RotationOffer.Hold) -> some View {
        GeometryReader { geo in
            let turned = hold != .portrait
            self
                .frame(width: turned ? geo.size.height : geo.size.width,
                       height: turned ? geo.size.width : geo.size.height)
                .rotationEffect(hold.angle)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
#endif
