import Foundation

/// Issue #6 — the iPhone Duo seam.
///
/// `ShotWorkspaceLayout` is the *single* layout-adaptation boundary between
/// presentation geometry and domain state. Nothing in the app reads a fold,
/// hinge, or second-display API (none are finalized); the app only ever asks
/// this enum which pane a piece of content belongs to for the current mode.
///
/// Documented two-pane specification (future iPhone Duo hardware):
/// - **Primary display**: the live shot timer, first-drop/stop controls, and
///   the active capture form — everything operated one-handed mid-shot.
/// - **Context display**: the dialed-in recipe, per-bean shot history entry,
///   the adjustment rationale for the current review, and status messages.
///
/// On standard iPhone displays the mode is always `.compact`: every content
/// collapses into the single primary pane in the documented order below.
/// Switching modes is a presentation-geometry change only; it must never
/// reset the timer, discard a draft, or clear a comparison selection (see
/// `ShotWorkspaceCoordinator`).
public enum WorkspaceContent: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case shotHistoryAccess
    case recipeContext
    case shotTimer
    case captureForm
    case adjustmentRationale
    case shotMessage
    case captureControls
}

public enum WorkspacePane: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case primary
    case context
}

public enum ShotWorkspaceLayoutMode: String, Codable, Equatable, Sendable {
    /// Single-pane presentation on standard iPhone displays.
    case compact
    /// Documented two-pane presentation reserved for dual-screen-capable
    /// iPhone Duo geometry. Not reachable on standard iPhones.
    case dualScreen
}

/// The capability probe the layout consults when selecting a mode. Only the
/// standard case is currently realizable; `dualScreenCapable` exists so the
/// future adapter plugs in here without touching domain or view code.
public enum WorkspaceDisplayCapability: String, Equatable, Sendable {
    case standard
    case dualScreenCapable
}

public enum ShotWorkspaceLayout {
    /// Capability → mode selection. Standard iPhones are always compact.
    public static func mode(for capability: WorkspaceDisplayCapability) -> ShotWorkspaceLayoutMode {
        switch capability {
        case .standard: .compact
        case .dualScreenCapable: .dualScreen
        }
    }

    /// Ordered contents of one pane. In compact mode everything collapses
    /// into the primary pane and the context pane is empty.
    public static func visibleContents(mode: ShotWorkspaceLayoutMode, pane: WorkspacePane) -> [WorkspaceContent] {
        switch mode {
        case .compact:
            guard pane == .primary else { return [] }
            return [
                .shotHistoryAccess,
                .recipeContext,
                .shotTimer,
                .captureForm,
                .adjustmentRationale,
                .shotMessage,
                .captureControls,
            ]
        case .dualScreen:
            switch pane {
            case .primary:
                return [.shotTimer, .captureForm, .captureControls]
            case .context:
                return [.recipeContext, .shotHistoryAccess, .adjustmentRationale, .shotMessage]
            }
        }
    }

    /// Where a piece of content renders for a given mode. Compact collapses
    /// every content onto the primary pane.
    public static func pane(containing content: WorkspaceContent, mode: ShotWorkspaceLayoutMode) -> WorkspacePane {
        switch mode {
        case .compact:
            .primary
        case .dualScreen:
            visibleContents(mode: .dualScreen, pane: .primary).contains(content) ? .primary : .context
        }
    }
}
