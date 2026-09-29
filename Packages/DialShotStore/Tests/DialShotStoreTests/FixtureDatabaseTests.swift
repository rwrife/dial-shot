import Foundation
import Testing
import GRDB
import DialShotKit
@testable import DialShotStore

/// Verifies the committed regression fixture (`Fixtures/v1_fixture.sqlite`)
/// against the current schema migrations, and asserts the pre-seeded
/// beans, grinders, baskets, recipes, and immutable shot attempts (with
/// their deterministic suggested adjustments) round-trip exactly.
@Suite("Committed fixture database")
struct FixtureDatabaseTests {
    private func openFixtureCopy() throws -> DatabaseQueue {
        guard let fixtureURL = Bundle.module.url(forResource: "v1_fixture", withExtension: "sqlite", subdirectory: "Fixtures") else {
            Issue.record("Committed fixture v1_fixture.sqlite not found in test bundle resources")
            throw DialShotStoreError.missingReference("v1_fixture.sqlite")
        }

        let workingCopy = FileManager.default.temporaryDirectory
            .appendingPathComponent("dialshot-fixture-\(UUID().uuidString).sqlite")
        try FileManager.default.copyItem(at: fixtureURL, to: workingCopy)

        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let queue = try DatabaseQueue(path: workingCopy.path, configuration: configuration)
        // Test fixtures may lag one migration behind HEAD; bring the working
        // copy to current schema so readers can decode optional newer columns.
        try DialShotDatabaseMigrator.migrator.migrate(queue)
        return queue
    }

    @Test("committed fixture migrates cleanly to the current schema head")
    func fixtureMigratesToHead() throws {
        let queue = try openFixtureCopy()

        // Applying migrations to an already-current fixture must be a no-op
        // (forward-only, idempotent) and must not lose any seeded data.
        try DialShotDatabaseMigrator.migrator.migrate(queue)

        let appliedIdentifiers = try queue.read { db in
            try DialShotDatabaseMigrator.migrator.appliedIdentifiers(db)
        }
        #expect(appliedIdentifiers == Set(DialShotDatabaseMigrator.identifiers))
    }

    @Test("committed fixture contains the exact seeded bean bags and grinder/basket profiles")
    func fixtureSeedsProfiles() throws {
        let queue = try openFixtureCopy()
        let beans = SQLiteBeanRepository(writer: queue)
        let grinders = SQLiteGrinderRepository(writer: queue)
        let baskets = SQLiteBasketRepository(writer: queue)

        #expect(try beans.get(id: StoreFixture.beanEthiopia.id) == StoreFixture.beanEthiopia)
        #expect(try beans.get(id: StoreFixture.beanColombia.id) == StoreFixture.beanColombia)
        #expect(try beans.list().count == 2)

        #expect(try grinders.get(id: StoreFixture.grinderNiche.id) == StoreFixture.grinderNiche)
        #expect(try baskets.get(id: StoreFixture.basketVST18.id) == StoreFixture.basketVST18)
    }

    @Test("committed fixture contains the exact seeded recipes")
    func fixtureSeedsRecipes() throws {
        let queue = try openFixtureCopy()
        let recipes = SQLiteRecipeRepository(writer: queue)

        #expect(try recipes.get(id: StoreFixture.recipeEthiopia.id) == StoreFixture.recipeEthiopia)
        #expect(try recipes.get(id: StoreFixture.recipeColombia.id) == StoreFixture.recipeColombia)
        #expect(try recipes.list(beanID: nil).count == 2)
    }

    @Test("committed fixture shots round-trip with their exact stored suggested adjustment")
    func fixtureShotsCarryStoredSuggestions() throws {
        let queue = try openFixtureCopy()
        let shots = SQLiteShotRepository(writer: queue)

        for expectedAttempt in StoreFixture.allShots {
            let record = try shots.get(id: expectedAttempt.id)
            #expect(record?.attempt == expectedAttempt)

            let expectedSuggestion = DialInEngine.suggest(for: expectedAttempt)
            #expect(record?.suggestion == expectedSuggestion)
        }

        #expect(try shots.count(beanID: nil) == 4)
    }

    @Test("fixture's sour/fast shot deterministically triggers a finer-grind suggestion")
    func fixtureSourFastShotTriggersFinerGrind() throws {
        let queue = try openFixtureCopy()
        let shots = SQLiteShotRepository(writer: queue)
        let record = try shots.get(id: StoreFixture.shotSourFast.id)

        guard case .adjustment(let adjustment) = record?.suggestion else {
            Issue.record("Expected an adjustment suggestion for the sour/fast shot")
            return
        }
        #expect(adjustment.action == .grindFiner)
        #expect(adjustment.rule == .underExtractedFastFlow)
    }

    @Test("fixture's conflicting-evidence shot yields an explicit unknown state, not a guess")
    func fixtureConflictingShotYieldsInsufficientEvidence() throws {
        let queue = try openFixtureCopy()
        let shots = SQLiteShotRepository(writer: queue)
        let record = try shots.get(id: StoreFixture.shotConflicting.id)

        #expect(record?.suggestion.isInsufficientEvidence == true)
    }
}
