/// DialShotKit — pure-domain core for Dial Shot.
///
/// Issue #1 shipped the skeleton namespace so CI has a real, testable
/// target. Issue #2 adds the immutable shot/recipe models
/// (`DomainModels.swift`), decimal-exact dose/yield/ratio math
/// (`BrewRatio.swift`), and the deterministic at-most-one-adjustment
/// `DialInEngine` (`DialInEngine.swift`). The monotonic-clock timer
/// reducer and the versioned backup codec land with the capture-workflow
/// and ownership/export milestones. The GRDB store is issue #3
/// (`DialShotStore`) and lives outside this package.
public enum DialShotKit {
    /// Namespace marker for the domain layer.
    public static let domain = "DialShotKit"

    /// Current build/CI milestone marker consumed by the app's debug surface.
    public static let milestone = "M1-domain-engine"
}
