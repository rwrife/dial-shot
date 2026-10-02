import Foundation
import XCTest
@testable import DialShotKit

/// Issue #6: timer state, the active draft, and the comparison selection live
/// in an environment-level coordinator that survives view-hierarchy rebuilds
/// and layout switches. Layout transitions are presentation-geometry only and
/// must never reset an active shot, discard a draft, or clear a selection.
///
/// XCTest on Linux cannot discover `@MainActor` test methods, so each test
/// body enters main-actor isolation explicitly via `MainActor.assumeIsolated`
/// (XCTest runs tests on the main thread on both platforms).
final class WorkspaceCoordinatorTests: XCTestCase {
    private func snapshot() throws -> RecipeSnapshot {
        try RecipeSnapshot(
            beanID: BeanBag.ID(),
            grinderID: GrinderProfile.ID(),
            basketID: BasketProfile.ID(),
            doseGrams: 18,
            targetYieldGrams: 36,
            targetTimeSeconds: 30
        )
    }

    func testFreshCoordinatorIsCompactWithNoDraftOrSelection() {
        MainActor.assumeIsolated {
            let coordinator = ShotWorkspaceCoordinator()
            XCTAssertEqual(coordinator.layoutMode, .compact)
            XCTAssertNil(coordinator.draft)
            XCTAssertEqual(coordinator.yieldInputText, "")
            XCTAssertTrue(coordinator.comparisonSelection.isEmpty)
        }
    }

    func testLayoutSwitchPreservesRunningTimerElapsedAndFirstDrop() throws {
        let recipe = try snapshot()
        MainActor.assumeIsolated {
            let coordinator = ShotWorkspaceCoordinator()
            coordinator.installDraft(recipe: recipe)
            coordinator.draft?.start(at: 100)
            XCTAssertEqual(coordinator.draft?.markFirstDrop(at: 104), true)
            XCTAssertEqual(coordinator.draft?.elapsedSeconds(at: 107), 7)

            coordinator.switchLayout(to: .dualScreen)
            // Layout flipped; the running timer keeps advancing from the same origin.
            XCTAssertEqual(coordinator.layoutMode, .dualScreen)
            XCTAssertEqual(coordinator.draft?.timer.phase, .running)
            XCTAssertEqual(coordinator.draft?.timer.firstDropSeconds, 4)
            XCTAssertEqual(coordinator.draft?.elapsedSeconds(at: 110), 10)

            coordinator.switchLayout(to: .compact)
            XCTAssertEqual(coordinator.draft?.timer.phase, .running)
            XCTAssertEqual(coordinator.draft?.elapsedSeconds(at: 113), 13)
        }
    }

    func testLayoutSwitchPreservesStoppedTimerAndDraftInputFields() throws {
        let recipe = try snapshot()
        MainActor.assumeIsolated {
            let coordinator = ShotWorkspaceCoordinator()
            coordinator.installDraft(recipe: recipe)
            coordinator.draft?.start(at: 50)
            coordinator.draft?.stop(at: 82)
            coordinator.yieldInputText = "34.5"
            coordinator.draft?.notes.insert(.sour)
            coordinator.draft?.flowVerdict = .fast

            coordinator.switchLayout(to: .dualScreen)
            coordinator.switchLayout(to: .compact)

            XCTAssertEqual(coordinator.draft?.timer.phase, .stopped)
            XCTAssertEqual(coordinator.draft?.elapsedSeconds(), 32)
            XCTAssertEqual(coordinator.yieldInputText, "34.5")
            XCTAssertEqual(coordinator.draft?.notes, [.sour])
            XCTAssertEqual(coordinator.draft?.flowVerdict, .fast)
        }
    }

    func testLayoutSwitchPreservesComparisonSelection() {
        MainActor.assumeIsolated {
            let coordinator = ShotWorkspaceCoordinator()
            let ids = (0..<2).map { _ in UUID() }
            coordinator.toggleComparisonSelection(ids[0])
            coordinator.toggleComparisonSelection(ids[1])

            coordinator.switchLayout(to: .dualScreen)
            XCTAssertEqual(coordinator.comparisonSelection, Set(ids))
        }
    }

    func testLayoutSwitchPreservesSelectedBean() {
        MainActor.assumeIsolated {
            let coordinator = ShotWorkspaceCoordinator()
            let bean = BeanBag.ID()
            coordinator.selectedBeanID = bean
            coordinator.switchLayout(to: .dualScreen)
            XCTAssertEqual(coordinator.selectedBeanID, bean)
        }
    }

    func testComparisonSelectionTogglesUpToTwoAndPrunesToVisible() {
        MainActor.assumeIsolated {
            let coordinator = ShotWorkspaceCoordinator()
            let a = UUID(), b = UUID(), c = UUID()
            coordinator.toggleComparisonSelection(a)
            coordinator.toggleComparisonSelection(b)
            coordinator.toggleComparisonSelection(c)
            XCTAssertEqual(coordinator.comparisonSelection.count, 2, "selection is capped at two shots")

            coordinator.toggleComparisonSelection(a)
            XCTAssertEqual(coordinator.comparisonSelection, [b])

            coordinator.toggleComparisonSelection(c)
            coordinator.pruneComparisonSelection(to: [b])
            XCTAssertEqual(coordinator.comparisonSelection, [b])

            coordinator.clearComparisonSelection()
            XCTAssertTrue(coordinator.comparisonSelection.isEmpty)
        }
    }

    func testInstallDraftReplacesCaptureAndClearsYieldInputOnly() throws {
        let recipe = try snapshot()
        MainActor.assumeIsolated {
            let coordinator = ShotWorkspaceCoordinator()
            coordinator.installDraft(recipe: recipe)
            coordinator.draft?.start(at: 10)
            coordinator.draft?.stop(at: 20)
            coordinator.yieldInputText = "40"

            coordinator.installDraft(recipe: recipe)
            XCTAssertNil(coordinator.draft?.timer.firstDropSeconds)
            XCTAssertEqual(coordinator.draft?.timer.phase, .idle)
            XCTAssertEqual(coordinator.yieldInputText, "")
            // Comparison selection is not draft state; replacing the draft keeps it.
            coordinator.toggleComparisonSelection(UUID())
            coordinator.installDraft(recipe: recipe)
            XCTAssertEqual(coordinator.comparisonSelection.count, 1)
        }
    }

    func testLayoutSwitchIsIdempotentAndDeterministic() throws {
        let recipe = try snapshot()
        MainActor.assumeIsolated {
            let coordinator = ShotWorkspaceCoordinator(mode: .dualScreen)
            coordinator.installDraft(recipe: recipe)
            coordinator.draft?.start(at: 0)
            coordinator.switchLayout(to: .dualScreen)
            XCTAssertEqual(coordinator.layoutMode, .dualScreen)
            XCTAssertEqual(coordinator.draft?.timer.phase, .running)
            XCTAssertEqual(coordinator.draft?.elapsedSeconds(at: 5), 5)
        }
    }
}
