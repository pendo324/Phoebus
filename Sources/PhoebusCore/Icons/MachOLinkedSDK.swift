import Foundation
#if canImport(MachO)
import MachO
#endif

/// Reads the running executable's own linked SDK version, by walking the
/// Mach-O load commands for `LC_BUILD_VERSION` (falling back to
/// `LC_VERSION_MIN_IPHONEOS`) and returning the `sdk` field, as Reborn does
/// to decide whether the app opts into the iOS 26 design system.
///
/// The deployment target is a source constant, while this is what the
/// linker recorded and what UIKit reads; when they disagree, UIKit follows
/// the binary.
public enum MachOLinkedSDK {
    public struct Version: Equatable, Sendable {
        public let major: Int
        public let minor: Int
        public let patch: Int

        public init(major: Int, minor: Int, patch: Int) {
            self.major = major
            self.minor = minor
            self.patch = patch
        }
    }

    /// Decodes Mach-O's packed `xxxx.yy.zz` version field.
    ///
    /// Split out from the image walk so it can be tested directly: the
    /// walk itself can only ever return this process's own value, which
    /// makes it useless as a test subject.
    public static func decode(_ packed: UInt32) -> Version {
        Version(major: Int(packed >> 16),
                minor: Int((packed >> 8) & 0xFF),
                patch: Int(packed & 0xFF))
    }

    /// The iOS (or iOS Simulator) SDK this executable was linked
    /// against, or `nil` if it could not be determined.
    public static func iOSSDKVersion() -> Version? {
        #if canImport(MachO) && canImport(Darwin)
        // Image 0 is the main executable, which is the one whose linked
        // SDK governs the app's UIKit behaviour. A framework's own
        // build version is irrelevant here.
        guard let header = _dyld_get_image_header(0) else { return nil }
        return header.withMemoryRebound(to: mach_header_64.self, capacity: 1) { header64 -> Version? in
            var cursor = UnsafeRawPointer(header64).advanced(by: MemoryLayout<mach_header_64>.size)
            for _ in 0..<Int(header64.pointee.ncmds) {
                let command = cursor.assumingMemoryBound(to: load_command.self).pointee
                if command.cmd == UInt32(LC_BUILD_VERSION) {
                    let build = cursor.assumingMemoryBound(to: build_version_command.self).pointee
                    if build.platform == UInt32(PLATFORM_IOS)
                        || build.platform == UInt32(PLATFORM_IOSSIMULATOR) {
                        return decode(build.sdk)
                    }
                }
                cursor = cursor.advanced(by: Int(command.cmdsize))
            }
            return nil
        }
        #else
        return nil
        #endif
    }
}
