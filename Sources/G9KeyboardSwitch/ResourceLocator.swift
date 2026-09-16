import Foundation

enum ResourceLocator {
    /// Resolve the bundled `m1ddc` executable across layouts (.app bundle,
    /// SwiftPM resource bundle, or an explicit env override for development).
    /// Ensures the resolved file is executable.
    static func m1ddcURL() -> URL? {
        var candidate: URL?

        if let override = ProcessInfo.processInfo.environment["G9_M1DDC_PATH"] {
            candidate = URL(fileURLWithPath: override)
        } else if let u = Bundle.main.url(forResource: "m1ddc", withExtension: nil) {
            candidate = u
        } else if let u = Bundle.module.url(forResource: "m1ddc", withExtension: nil) {
            candidate = u
        }

        guard let url = candidate, FileManager.default.fileExists(atPath: url.path) else { return nil }
        ensureExecutable(url)
        return url
    }

    private static func ensureExecutable(_ url: URL) {
        let fm = FileManager.default
        if let attrs = try? fm.attributesOfItem(atPath: url.path),
           let perms = attrs[.posixPermissions] as? NSNumber,
           (perms.uint16Value & 0o111) == 0 {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
    }
}
