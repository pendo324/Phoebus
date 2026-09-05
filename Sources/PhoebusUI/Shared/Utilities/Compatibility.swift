import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// Availability shims.
//
// The app builds against the iOS 26 SDK but supports iOS 17 and later
// (the deployment target can be lowered on the built app). Anything
// newer than iOS 17 goes through one of these helpers, which use the
// newer API where the OS has it and a close equivalent otherwise.
// The smoke test fails if a newer-only API is used outside this file
// or an `#available` block.

// MARK: - iOS 17 baseline wrappers

extension View {
    /// Inline navigation title.
    func navigationBarTitleDisplayModeIfAvailable() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func fullScreenCoverIfAvailable<Content: View>(isPresented: Binding<Bool>,
                                                   @ViewBuilder content: @escaping () -> Content) -> some View {
        #if canImport(UIKit)
        fullScreenCover(isPresented: isPresented, content: content)
        #else
        sheet(isPresented: isPresented, content: content)
        #endif
    }

    /// Item-based variant: use it when the presented content depends on
    /// state set by the same tap, which the `isPresented` form reads
    /// before the tap's writes land.
    @ViewBuilder
    func fullScreenCoverIfAvailable<Item: Identifiable, Content: View>(
        item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if canImport(UIKit)
        fullScreenCover(item: item, content: content)
        #else
        sheet(item: item, content: content)
        #endif
    }

    @ViewBuilder
    func statusBarHiddenIfAvailable() -> some View {
        #if canImport(UIKit)
        statusBarHidden(true)
        #else
        self
        #endif
    }

    /// Medium + large detents with a grabber and a 24pt corner radius.
    func presentationDetentsIfAvailable() -> some View {
        presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadiusIfAvailable(24)
    }

    func presentationCornerRadiusIfAvailable(_ radius: CGFloat) -> some View {
        presentationCornerRadius(radius)
    }

    /// Short content doesn't bounce; long content still scrolls.
    func scrollBounceBehaviorBasedOnSizeIfAvailable() -> some View {
        scrollBounceBehavior(.basedOnSize)
    }
}

extension Color {
    static var secondarySystemBackgroundIfAvailable: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondarySystemBackground)
        #else
        Color.gray.opacity(0.15)
        #endif
    }

    static var systemBackgroundIfAvailable: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemBackground)
        #else
        Color.white
        #endif
    }
}

struct ContentUnavailableViewIfAvailable: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
    }
}

// MARK: - iOS 18+

extension View {
    /// `onScrollGeometryChange` on iOS 18+. Below that the transform is
    /// never evaluated and `action` never fires, so callers must start
    /// from a sensible resting state.
    @ViewBuilder
    func onScrollGeometryChangeIfAvailable<T: Equatable>(
        for type: T.Type,
        of transform: @escaping (ScrollGeometryCompat) -> T,
        action: @escaping (T, T) -> Void
    ) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            onScrollGeometryChange(for: type, of: { transform(ScrollGeometryCompat($0)) }, action: action)
        } else {
            self
        }
    }
}

/// The parts of iOS 18's `ScrollGeometry` callers use, so closures can be
/// written without their own availability checks.
struct ScrollGeometryCompat {
    let contentOffset: CGPoint
    let contentInsets: EdgeInsets
    let containerSize: CGSize

    @available(iOS 18.0, macOS 15.0, *)
    init(_ geometry: ScrollGeometry) {
        contentOffset = geometry.contentOffset
        contentInsets = geometry.contentInsets
        containerSize = geometry.containerSize
    }
}
