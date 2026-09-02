import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PhoebusCore

// Standalone Linux-runnable smoke test for PhoebusCore. The swift-testing
// test target pulls in the whole package graph (including SwiftUI-dependent
// PhoebusUI), which cannot build on Linux; this executable depends only on
// PhoebusCore and checks JSON decoding and comment-tree logic on the host.

// Every run starts from empty settings so values left behind by a previous
// run cannot change what the next run sees.
for key in UserDefaults.standard.dictionaryRepresentation().keys {
    UserDefaults.standard.removeObject(forKey: key)
}

nonisolated(unsafe) var failures = 0
func check(_ name: String, _ condition: @autoclosure () -> Bool) {
    if condition() {
        print("PASS: \(name)")
    } else {
        print("FAIL: \(name)")
        failures += 1
    }
}
