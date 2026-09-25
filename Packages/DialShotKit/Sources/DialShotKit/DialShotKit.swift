/// DialShotKit — pure-domain core for Dial Shot.
///
/// Issue #1 ships only the skeleton namespace so CI has a real, testable
/// target. Issue #2 (domain) lands the immutable shot/recipe models,
/// decimal-safe dose/yield/ratio math, the monotonic-clock timer reducer,
/// and the deterministic at-most-one-adjustment DialInEngine here, plus
/// the versioned backup codec. The GRDB store is issue #3 (DialShotStore)
/// and lives outside this package.
public enum DialShotKit {
    /// Namespace marker for the domain layer.
    public static let domain = "DialShotKit"

    /// Current build/CI milestone marker consumed by the app's debug surface.
    public static let milestone = "M0-skeleton"
}
