import Foundation

extension Bundle {
    /// Marketing version, e.g. "2.0".
    ///
    /// Read from the bundle rather than written into each view. Hardcoded
    /// version strings had already drifted twice: the palette said "v1.0" and
    /// the About tab "Version 1.0.0" while the shipped DMG was being named
    /// v1.7 — and none of the three agreed with MARKETING_VERSION.
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    /// Build number, e.g. "3". Distinguishes two builds sharing a version.
    var appBuild: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    }
}
