import Foundation

/// Splits a "•••" menu's rows into the separator-delimited groups Apollo draws.
///
/// Lives in PhoebusCore so the smoke test (which links PhoebusCore only, as
/// PhoebusUI needs UIKit) can exercise the rule as a pure function over indices.
///
/// Reborn marks a row as its own separated group with
/// `spec.inlineSection = YES`, which becomes a `UIMenuOptionsDisplayInline`
/// child that UIKit renders with separators around it.
public enum ApolloMenuSectioning {
    /// Groups `count` rows, where `startsSection(i)` is true for a row
    /// that OPENS a new group.
    ///
    /// A marker on the very first row does not produce an empty leading
    /// group, which would draw a stray separator above the first row.
    public static func sections(count: Int,
                                startsSection: (Int) -> Bool) -> [[Int]] {
        var sections: [[Int]] = []
        var current: [Int] = []
        for index in 0..<max(0, count) {
            if startsSection(index), !current.isEmpty {
                sections.append(current)
                current = []
            }
            current.append(index)
        }
        if !current.isEmpty { sections.append(current) }
        return sections
    }
}
