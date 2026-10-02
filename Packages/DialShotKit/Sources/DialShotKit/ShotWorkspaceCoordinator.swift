import Foundation
import Observation

/// Issue #6 — environment-level continuity coordinator.
///
/// Timer state, the active capture draft, the yield input, and the
/// comparison selection live here, above the view hierarchy, so that view
/// rebuilds and `ShotWorkspaceLayout` mode switches cannot reset an active
/// shot, discard draft input, or clear a selection. `switchLayout(to:)` only
/// changes presentation geometry and never touches state.
@MainActor
@Observable
public final class ShotWorkspaceCoordinator {
    public private(set) var layoutMode: ShotWorkspaceLayoutMode

    /// The unsaved capture draft (timer + observed values). `nil` until the
    /// store provides the active recipe.
    public var draft: ShotCapture?

    /// Raw yield-field text kept outside the draft so a rejected review
    /// leaves exactly what the user typed on screen.
    public var yieldInputText: String = ""

    /// Shots selected for two-shot comparison (max two). View code enforces
    /// bean scoping; the coordinator owns membership and survives layout
    /// switches and view rebuilds.
    public var comparisonSelection: Set<UUID> = []

    /// Bean whose recipe/history the workspace is currently inspecting.
    /// Layout switches and view rebuilds keep this stable.
    public var selectedBeanID: BeanBag.ID?

    public init(mode: ShotWorkspaceLayoutMode = .compact) {
        layoutMode = mode
    }

    /// Presentation-only transition. Deliberately touches nothing but the
    /// mode so state continuity is structurally guaranteed.
    public func switchLayout(to mode: ShotWorkspaceLayoutMode) {
        layoutMode = mode
    }

    /// Replaces the draft with a fresh capture for the active recipe and
    /// clears only the transient yield text. Comparison selection survives.
    public func installDraft(recipe: RecipeSnapshot) {
        draft = ShotCapture(recipe: recipe)
        yieldInputText = ""
    }

    public func toggleComparisonSelection(_ id: UUID) {
        if comparisonSelection.contains(id) {
            comparisonSelection.remove(id)
        } else if comparisonSelection.count < 2 {
            comparisonSelection.insert(id)
        }
    }

    /// Drops selected shots that are no longer visible under current filters.
    public func pruneComparisonSelection(to visibleIDs: some Sequence<UUID>) {
        comparisonSelection.formIntersection(Set(visibleIDs))
    }

    public func clearComparisonSelection() {
        comparisonSelection.removeAll()
    }
}
