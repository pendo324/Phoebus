import SwiftUI

extension Binding {
    /// True while the optional holds a value; setting false clears it.
    /// Drives `isPresented:` presentations from an optional item.
    func isPresent<Wrapped>() -> Binding<Bool> where Value == Wrapped? {
        Binding<Bool>(
            get: { wrappedValue != nil },
            set: { if !$0 { wrappedValue = nil } }
        )
    }
}
