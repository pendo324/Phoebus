import Foundation

/// Decodes an array, skipping elements that don't decode, so one odd
/// entry doesn't lose the rest.
public struct LossyArray<Element: Decodable>: Decodable {
    public let elements: [Element]

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else {
                // Step past the bad element.
                _ = try? container.decode(Skipped.self)
            }
        }
        self.elements = elements
    }

    private struct Skipped: Decodable {
        init(from decoder: Decoder) throws {}
    }
}

extension LossyArray: Sendable where Element: Sendable {}
