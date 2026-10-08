import Foundation
import PhoebusCore

// The release channel CI stamps into Info.plist.
@MainActor func checkBuildChannelParsing() async throws {
    check("stable channel parses", BuildChannel(infoDictionary: ["PhoebusBuildChannel": "stable"]) == .stable)
    check("nightly channel parses", BuildChannel(infoDictionary: ["PhoebusBuildChannel": "nightly"]) == .nightly)
    check("channel parsing ignores case and padding", BuildChannel(infoDictionary: ["PhoebusBuildChannel": " Nightly "]) == .nightly)
    check("an unknown channel is no channel", BuildChannel(infoDictionary: ["PhoebusBuildChannel": "beta"]) == nil)
    check("a non-string channel is no channel", BuildChannel(infoDictionary: ["PhoebusBuildChannel": 1]) == nil)
    check("a build without the key has no channel", BuildChannel(infoDictionary: ["CFBundleVersion": "7"]) == nil)
    check("no Info.plist means no channel", BuildChannel(infoDictionary: nil) == nil)
}
