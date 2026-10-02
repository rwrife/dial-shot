import Foundation
import XCTest
@testable import DialShotKit

/// Issue #6: `ShotWorkspaceLayout` is the single layout-adaptation seam.
/// The pane map and mode selection are pure and deterministic so they are
/// verifiable without any fold API, simulator geometry, or display hardware.
final class WorkspaceLayoutTests: XCTestCase {
    func testStandardDisplayIsAlwaysCompact() {
        XCTAssertEqual(ShotWorkspaceLayout.mode(for: .standard), .compact)
    }

    func testDualScreenCapableDisplaySelectsDocumentedDualMode() {
        XCTAssertEqual(ShotWorkspaceLayout.mode(for: .dualScreenCapable), .dualScreen)
    }

    func testDualPrimaryPaneHoldsOnlyTimerAndCaptureControls() {
        XCTAssertEqual(
            ShotWorkspaceLayout.visibleContents(mode: .dualScreen, pane: .primary),
            [.shotTimer, .captureForm, .captureControls]
        )
    }

    func testDualContextPaneHoldsRecipeHistoryRationaleAndMessage() {
        XCTAssertEqual(
            ShotWorkspaceLayout.visibleContents(mode: .dualScreen, pane: .context),
            [.recipeContext, .shotHistoryAccess, .adjustmentRationale, .shotMessage]
        )
    }

    func testDualPaneAssignmentIsAnExhaustiveDisjointPartition() {
        let primary = Set(ShotWorkspaceLayout.visibleContents(mode: .dualScreen, pane: .primary))
        let context = Set(ShotWorkspaceLayout.visibleContents(mode: .dualScreen, pane: .context))
        XCTAssertEqual(primary.isDisjoint(with: context), true)
        XCTAssertEqual(primary.union(context), Set(WorkspaceContent.allCases))
        XCTAssertEqual(WorkspaceContent.allCases.count, primary.count + context.count)
    }

    func testCompactModeCollapsesEveryContentIntoTheSinglePaneInDocumentedOrder() {
        XCTAssertEqual(
            ShotWorkspaceLayout.visibleContents(mode: .compact, pane: .primary),
            [.shotHistoryAccess, .recipeContext, .shotTimer, .captureForm, .adjustmentRationale, .shotMessage, .captureControls]
        )
        XCTAssertEqual(ShotWorkspaceLayout.visibleContents(mode: .compact, pane: .context), [])
    }

    func testPaneResolutionMatchesDualMapAndCollapsesInCompact() {
        for content in WorkspaceContent.allCases {
            let dualPane = ShotWorkspaceLayout.pane(containing: content, mode: .dualScreen)
            XCTAssertEqual(ShotWorkspaceLayout.visibleContents(mode: .dualScreen, pane: dualPane).contains(content), true, "\(content)")
            XCTAssertEqual(ShotWorkspaceLayout.pane(containing: content, mode: .compact), .primary)
        }
    }
}
