import Foundation
import XCTest
import GRDB
import DialShotKit
@testable import DialShotStore

/// Issue #7: versioned JSON backup and transactional restore.
///
/// Everything here runs against a real GRDB SQLite queue so the transaction
/// guarantees, foreign-key enforcement, and decimal/date fidelity are proven
/// on the same storage layer the app ships — not against a mock that agrees
/// with the code under test.
final class BackupTests: XCTestCase {
    private var queue: DatabaseQueue!
    private var beans: SQLiteBeanRepository!
    private var grinders: SQLiteGrinderRepository!
    private var baskets: SQLiteBasketRepository!
    private var recipes: SQLiteRecipeRepository!
    private var shots: SQLiteShotRepository!

    private let beanID = BeanBag.ID(rawValue: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
    private let otherBeanID = BeanBag.ID(rawValue: UUID(uuidString: "12121212-1212-1212-1212-121212121212")!)
    private let grinderID = GrinderProfile.ID(rawValue: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)
    private let basketID = BasketProfile.ID(rawValue: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!)
    private let recipeID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    private let otherRecipeID = UUID(uuidString: "45454545-4545-4545-4545-454545454545")!
    private let shotID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!

    override func setUpWithError() throws {
        queue = try DialShotDatabaseFactory.makeQueue()
        beans = SQLiteBeanRepository(writer: queue)
        grinders = SQLiteGrinderRepository(writer: queue)
        baskets = SQLiteBasketRepository(writer: queue)
        recipes = SQLiteRecipeRepository(writer: queue)
        shots = SQLiteShotRepository(writer: queue)
    }

    private func source() -> BackupSource {
        BackupSource(beans: beans, grinders: grinders, baskets: baskets, recipes: recipes, shots: shots, database: queue)
    }

    /// Seeds one bean, one grinder, one basket, a dialed-in recipe, and a
    /// saved shot with deterministic ids and timestamps.
    private func seedStore(roastDate: Date? = Date(timeIntervalSinceReferenceDate: 800_000_000)) throws {
        try grinders.save(GrinderProfile(id: grinderID, name: "1Z J-Mill", settingLabel: "7"))
        try baskets.save(BasketProfile(id: basketID, name: "18 g basket", nominalDoseGrams: Decimal(string: "18.5")!))
        try beans.save(BeanBag(id: beanID, name: "Ethiopia, Guji", roastDate: roastDate))
        let snapshot = try RecipeSnapshot(
            beanID: beanID, grinderID: grinderID, basketID: basketID,
            doseGrams: Decimal(string: "17.7")!, targetYieldGrams: Decimal(string: "35.4")!,
            targetTimeSeconds: 30
        )
        try recipes.save(RecipeRecord(id: recipeID, name: "Starter", snapshot: snapshot, createdAt: Date(timeIntervalSinceReferenceDate: 800_000_100)))
        try recipes.setActive(recipeID: recipeID, for: beanID)
        try recipes.setSelectedWorkspaceBeanID(beanID)

        let attempt = try ShotAttempt(
            id: shotID, recipe: snapshot, measuredYieldGrams: Decimal(string: "34")!,
            elapsedSeconds: 31, firstDropSeconds: 6,
            observation: SensoryObservation(tasteVerdict: .underExtracted, flowVerdict: .fast, notes: [.sour]),
            createdAt: Date(timeIntervalSinceReferenceDate: 800_000_200)
        )
        try shots.save(attempt)
    }

    // MARK: - Export

    func testExportCapturesEveryEntityAndCounts() throws {
        try seedStore()
        let document = try LocalBackup.document(from: source())
        XCTAssertEqual(document.schemaVersion, .v1)
        XCTAssertEqual(document.entityCounts, BackupEntityCounts(beans: 1, grinders: 1, baskets: 1, recipes: 1, shots: 1))
        XCTAssertEqual(document.selectedBeanID, beanID)
        let group = try XCTUnwrap(document.beanGroups.first)
        XCTAssertEqual(group.activeRecipeID, recipeID)
        XCTAssertEqual(group.bean.name, "Ethiopia, Guji")
    }

    func testExportProducerIsThisBundlesProduct() throws {
        try seedStore()
        let document = try LocalBackup.document(from: source())
        XCTAssertEqual(document.exportInfo.producerBundleID, "com.infinityball.dialshot")
    }

    func testEncodeDecodePreservesExactDecimalsIncludingNonTerminatingRatios() throws {
        try seedStore()
        let document = try LocalBackup.document(from: source())
        let data = try BackupJSONCodec.encode(document)
        let decoded = try BackupJSONCodec.decode(data)
        XCTAssertEqual(decoded, document)

        // Decimals must cross the boundary as exact text, not through the
        // default Double-based Decimal Codable conformance.
        let encoded = String(data: data, encoding: .utf8)!
        XCTAssertTrue(encoded.contains("\"doseGrams\" : \"17.7\""), "decimals export as exact text: \(encoded.prefix(400))")

        let shot = try XCTUnwrap(decoded.beanGroups.first?.shots.first)
        // The 34/17.7 ratio is non-terminating; equality against the original
        // proves the JSON boundary preserved it exactly.
        let originalShot = try XCTUnwrap(document.beanGroups.first?.shots.first)
        XCTAssertEqual(shot.attempt.brewRatio.value, originalShot.attempt.brewRatio.value)
    }

    func testEncodeDecodePreservesTimestampsBitExactly() throws {
        try seedStore()
        let document = try LocalBackup.document(from: source())
        let decoded = try BackupJSONCodec.decode(try BackupJSONCodec.encode(document))
        let originalShot = try XCTUnwrap(document.beanGroups.first?.shots.first)
        let decodedShot = try XCTUnwrap(decoded.beanGroups.first?.shots.first)
        // Exact Double equality — the same values SQLite stores as REAL.
        XCTAssertEqual(
            originalShot.attempt.createdAt.timeIntervalSinceReferenceDate.bitPattern,
            decodedShot.attempt.createdAt.timeIntervalSinceReferenceDate.bitPattern
        )
        XCTAssertEqual(
            originalShot.attempt.createdAt,
            decodedShot.attempt.createdAt
        )
    }

    func testExportIsDeterministicApartFromExportedAt() throws {
        try seedStore()
        let fixed = Date(timeIntervalSinceReferenceDate: 810_000_000)
        let a = try LocalBackup.document(from: source(), exportedAt: fixed)
        let b = try LocalBackup.document(from: source(), exportedAt: fixed)
        XCTAssertEqual(try BackupJSONCodec.encode(a), try BackupJSONCodec.encode(b))
    }

    func testEmptyStoreExportsValidEmptyDocument() throws {
        let document = try LocalBackup.document(from: source())
        XCTAssertEqual(document.entityCounts, .empty)
        let decoded = try BackupJSONCodec.decode(try BackupJSONCodec.encode(document))
        XCTAssertEqual(decoded.entityCounts, .empty)
    }

    // MARK: - Validation failures

    func testUnsupportedSchemaVersionIsRefused() throws {
        try seedStore()
        let data = try BackupJSONCodec.encode(try LocalBackup.document(from: source()))
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return XCTFail("export is not a JSON object")
        }
        json["schemaVersion"] = 99
        let tampered = try JSONSerialization.data(withJSONObject: json)
        XCTAssertThrowsError(try BackupJSONCodec.decode(tampered)) { error in
            XCTAssertEqual(error as? BackupValidationError, .unsupportedSchemaVersion(99))
        }
    }

    func testForeignProducerCannotEnterTheRestorePath() throws {
        try seedStore()
        let data = try BackupJSONCodec.encode(try LocalBackup.document(from: source()))
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var info = json["exportInfo"] as? [String: Any] else {
            return XCTFail("export is not a JSON object with exportInfo")
        }
        info["producerBundleID"] = "com.somebody.else"
        json["exportInfo"] = info
        let tampered = try JSONSerialization.data(withJSONObject: json)
        // Structurally fine, but the restore path refuses it.
        _ = try BackupJSONCodec.decode(tampered)
        XCTAssertThrowsError(try BackupJSONCodec.decodedForRestore(tampered)) { error in
            XCTAssertEqual(error as? BackupValidationError, .foreignProducer(bundleID: "com.somebody.else"))
        }
        XCTAssertThrowsError(try BackupJSONCodec.preview(tampered))
    }

    func testConflictingMetadataVersionIsRefused() throws {
        try seedStore()
        let data = try BackupJSONCodec.encode(try LocalBackup.document(from: source()))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var info = try XCTUnwrap(json["exportInfo"] as? [String: Any])
        info["schemaVersion"] = 99
        json["exportInfo"] = info
        XCTAssertThrowsError(try BackupJSONCodec.decode(JSONSerialization.data(withJSONObject: json))) { error in
            XCTAssertEqual(error as? BackupValidationError, .unsupportedSchemaVersion(99))
        }
    }

    func testDirectRestoreRejectsStructurallyInvalidDocumentWithoutTouchingStore() throws {
        try seedStore()
        let existing = try LocalBackup.document(from: source())
        let invalid = BackupDocument(grinders: [], baskets: existing.baskets,
            beanGroups: existing.beanGroups, selectedBeanID: existing.selectedBeanID)
        XCTAssertThrowsError(try LocalBackup.restore(invalid, into: queue))
        XCTAssertEqual(try shots.count(beanID: nil), 1)
        XCTAssertEqual(try recipes.active(for: beanID)?.id, recipeID)
    }

    func testDuplicateRecipeIDAcrossTwoBeansFailsDuringPreview() throws {
        try seedStore()
        let data = try BackupJSONCodec.encode(try LocalBackup.document(from: source()))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var groups = try XCTUnwrap(json["beanGroups"] as? [[String: Any]])
        var second = try XCTUnwrap(groups.first)
        var bean = try XCTUnwrap(second["bean"] as? [String: Any])
        // Domain ID is a rawValue-wrapped UUID in the Codable representation.
        bean["id"] = ["rawValue": otherBeanID.rawValue.uuidString]
        second["bean"] = bean
        var recipe = try XCTUnwrap((second["recipes"] as? [[String: Any]])?.first)
        recipe["beanID"] = otherBeanID.rawValue.uuidString
        second["recipes"] = [recipe]
        second["shots"] = []
        second["activeRecipeID"] = NSNull()
        groups.append(second)
        json["beanGroups"] = groups
        XCTAssertThrowsError(try BackupJSONCodec.preview(JSONSerialization.data(withJSONObject: json))) { error in
            XCTAssertEqual(error as? BackupValidationError,
                           .duplicateID(kind: "recipe", id: self.recipeID.uuidString))
        }
    }

    func testDanglingBeanReferenceInsideGroupIsRefused() throws {
        try seedStore()
        let data = try BackupJSONCodec.encode(try LocalBackup.document(from: source()))
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var groups = json["beanGroups"] as? [[String: Any]],
              var firstGroup = groups.first else {
            return XCTFail("export missing beanGroups")
        }
        // Repoint the recipe at a bean that is not in the file.
        var recipe = try XCTUnwrap(firstGroup["recipes"] as? [[String: Any]]).first!
        recipe["beanID"] = UUID().uuidString
        firstGroup["recipes"] = [recipe]
        groups[0] = firstGroup
        json["beanGroups"] = groups
        let tampered = try JSONSerialization.data(withJSONObject: json)
        XCTAssertThrowsError(try BackupJSONCodec.decode(tampered)) { error in
            guard case .danglingReference(let kind, _, "bean", _) = error as? BackupValidationError else {
                return XCTFail("expected dangling reference, got \(error)")
            }
            XCTAssertEqual(kind, "recipe")
        }
    }

    func testMissingGrinderForRecipeIsRefused() throws {
        try seedStore()
        let data = try BackupJSONCodec.encode(try LocalBackup.document(from: source()))
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return XCTFail("export is not a JSON object")
        }
        json["grinders"] = []
        let tampered = try JSONSerialization.data(withJSONObject: json)
        XCTAssertThrowsError(try BackupJSONCodec.decode(tampered)) { error in
            guard case .danglingReference(let kind, _, "grinder", _) = error as? BackupValidationError else {
                return XCTFail("expected dangling grinder reference, got \(error)")
            }
            XCTAssertEqual(kind, "recipe")
        }
    }

    func testDanglingActiveRecipeIsRefused() throws {
        try seedStore()
        let data = try BackupJSONCodec.encode(try LocalBackup.document(from: source()))
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var groups = json["beanGroups"] as? [[String: Any]],
              var firstGroup = groups.first else {
            return XCTFail("export missing beanGroups")
        }
        firstGroup["recipes"] = []
        groups[0] = firstGroup
        json["beanGroups"] = groups
        let tampered = try JSONSerialization.data(withJSONObject: json)
        XCTAssertThrowsError(try BackupJSONCodec.decode(tampered)) { error in
            guard case .activeRecipeNotFound = error as? BackupValidationError else {
                return XCTFail("expected activeRecipeNotFound, got \(error)")
            }
        }
    }

    func testRatioContradictingDoseYieldPairIsRefused() throws {
        try seedStore()
        let data = try BackupJSONCodec.encode(try LocalBackup.document(from: source()))
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var groups = json["beanGroups"] as? [[String: Any]],
              var firstGroup = groups.first,
              var shot = try XCTUnwrap(firstGroup["shots"] as? [[String: Any]]).first else {
            return XCTFail("export missing shots")
        }
        shot["brewRatioValue"] = "1" // contradicts measured 34 / dose 17.7
        firstGroup["shots"] = [shot]
        groups[0] = firstGroup
        json["beanGroups"] = groups
        let tampered = try JSONSerialization.data(withJSONObject: json)
        XCTAssertThrowsError(try BackupJSONCodec.decode(tampered)) { error in
            guard case .ratioMismatch = error as? BackupValidationError else {
                return XCTFail("expected ratioMismatch, got \(error)")
            }
        }
    }

    func testInvalidShotTimingIsRefusedByDomainValidator() throws {
        try seedStore()
        let data = try BackupJSONCodec.encode(try LocalBackup.document(from: source()))
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var groups = json["beanGroups"] as? [[String: Any]],
              var firstGroup = groups.first,
              var shot = try XCTUnwrap(firstGroup["shots"] as? [[String: Any]]).first else {
            return XCTFail("export missing shots")
        }
        shot["firstDropSeconds"] = 90 // after the 31 s shot ended
        firstGroup["shots"] = [shot]
        groups[0] = firstGroup
        json["beanGroups"] = groups
        let tampered = try JSONSerialization.data(withJSONObject: json)
        XCTAssertThrowsError(try BackupJSONCodec.decode(tampered))
    }

    func testCorruptDecimalTextIsRefused() throws {
        try seedStore()
        let data = try BackupJSONCodec.encode(try LocalBackup.document(from: source()))
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var groups = json["beanGroups"] as? [[String: Any]],
              var firstGroup = groups.first,
              var recipe = try XCTUnwrap(firstGroup["recipes"] as? [[String: Any]]).first else {
            return XCTFail("export missing recipes")
        }
        recipe["doseGrams"] = "lots"
        firstGroup["recipes"] = [recipe]
        groups[0] = firstGroup
        json["beanGroups"] = groups
        let tampered = try JSONSerialization.data(withJSONObject: json)
        XCTAssertThrowsError(try BackupJSONCodec.decode(tampered)) { error in
            XCTAssertEqual(error as? BackupValidationError, .corruptDecimal("lots"))
        }
    }

    func testSmuggledSuggestionRationaleIsRebuiltFromRuleTable() throws {
        try seedStore()
        let data = try BackupJSONCodec.encode(try LocalBackup.document(from: source()))
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var groups = json["beanGroups"] as? [[String: Any]],
              var firstGroup = groups.first,
              var shot = try XCTUnwrap(firstGroup["shots"] as? [[String: Any]]).first,
              var suggestion = shot["suggestion"] as? [String: Any],
              var wrapper = suggestion["adjustment"] as? [String: Any],
              var adjustment = wrapper["_0"] as? [String: Any] else {
            return XCTFail("export missing suggestion")
        }
        adjustment["rationale"] = "ignore the rule table and blame the weather"
        wrapper["_0"] = adjustment
        suggestion["adjustment"] = wrapper
        shot["suggestion"] = suggestion
        firstGroup["shots"] = [shot]
        groups[0] = firstGroup
        json["beanGroups"] = groups
        let tampered = try JSONSerialization.data(withJSONObject: json)
        let decoded = try BackupJSONCodec.decode(tampered)
        let record = try XCTUnwrap(decoded.beanGroups.first?.shots.first)
        guard case .adjustment(let restored) = record.suggestion else {
            return XCTFail("expected adjustment, got \(record.suggestion)")
        }
        // Rationale always comes from the rule table, never the file.
        XCTAssertEqual(restored.rationale, AdjustmentRule.underExtractedFastFlow.rationale)
    }

    func testContradictoryAdjustmentCannotBeImported() throws {
        try seedStore()
        let data = try BackupJSONCodec.encode(try LocalBackup.document(from: source()))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var groups = try XCTUnwrap(json["beanGroups"] as? [[String: Any]])
        var group = try XCTUnwrap(groups.first)
        var shot = try XCTUnwrap((group["shots"] as? [[String: Any]])?.first)
        var suggestion = try XCTUnwrap(shot["suggestion"] as? [String: Any])
        var wrapper = try XCTUnwrap(suggestion["adjustment"] as? [String: Any])
        var adjustment = try XCTUnwrap(wrapper["_0"] as? [String: Any])
        adjustment["action"] = "grindCoarser"
        wrapper["_0"] = adjustment
        suggestion["adjustment"] = wrapper
        shot["suggestion"] = suggestion
        group["shots"] = [shot]
        groups[0] = group
        json["beanGroups"] = groups
        XCTAssertThrowsError(try BackupJSONCodec.decode(JSONSerialization.data(withJSONObject: json))) { error in
            XCTAssertEqual(error as? BackupValidationError, .suggestionMismatch(shotID: self.shotID.uuidString))
        }
    }

    // MARK: - Restore

    func testPreviewReportsCountsBeforeAnythingIsTouched() throws {
        try seedStore()
        let data = try BackupJSONCodec.encode(try LocalBackup.document(from: source()))
        let preview = try BackupJSONCodec.preview(data)
        XCTAssertEqual(preview.schemaVersion, .v1)
        XCTAssertEqual(preview.producerBundleID, "com.infinityball.dialshot")
        XCTAssertEqual(preview.entityCounts, BackupEntityCounts(beans: 1, grinders: 1, baskets: 1, recipes: 1, shots: 1))
        // Preview must be pure: the live database is untouched.
        XCTAssertEqual(try shots.count(beanID: nil), 1)
        XCTAssertEqual(preview.entityCounts.previewSummary, "1 bean, 1 grinder, 1 basket, 1 recipe, 1 shot")
    }

    func testRestoreReplacesAllPreviousDataAndRoundTrips() throws {
        try seedStore()
        let exported = try LocalBackup.document(from: source(), exportedAt: Date(timeIntervalSinceReferenceDate: 810_000_000))

        // Diverge the live store: a new bean and shot the backup does not have.
        try beans.save(BeanBag(id: otherBeanID, name: "New bean"))
        let otherSnapshot = try RecipeSnapshot(beanID: otherBeanID, grinderID: grinderID, basketID: basketID, doseGrams: 18, targetYieldGrams: 36, targetTimeSeconds: 30)
        try recipes.save(RecipeRecord(id: otherRecipeID, name: "Other", snapshot: otherSnapshot, createdAt: Date()))
        try recipes.setActive(recipeID: otherRecipeID, for: otherBeanID)
        let newShot = try ShotAttempt(id: UUID(), recipe: otherSnapshot, measuredYieldGrams: 40, elapsedSeconds: 27, firstDropSeconds: nil, observation: .balanced, createdAt: Date(timeIntervalSinceReferenceDate: 900_000_000))
        try shots.save(newShot)
        XCTAssertEqual(try beans.list().count, 2)

        try LocalBackup.restore(exported, into: queue)

        // Everything re-read through the repositories matches the backup.
        let reexport = try LocalBackup.document(from: source(), exportedAt: exported.exportInfo.exportedAt)
        XCTAssertEqual(
            BackupDocument(schemaVersion: reexport.schemaVersion, exportInfo: exported.exportInfo, grinders: reexport.grinders, baskets: reexport.baskets, beanGroups: reexport.beanGroups, selectedBeanID: reexport.selectedBeanID),
            exported
        )
        // The post-backup bean/shot is gone — a replacement, not a merge.
        XCTAssertEqual(try beans.list().count, 1)
        XCTAssertNil(try shots.get(id: newShot.id))
        XCTAssertEqual(try recipes.active(for: beanID)?.id, recipeID)
        XCTAssertEqual(try recipes.selectedWorkspaceBeanID(), beanID)
    }

    func testRestoreAndVerifyPassesOnFaithfulExport() throws {
        try seedStore()
        let exported = try LocalBackup.document(from: source())
        XCTAssertNoThrow(try LocalBackup.restoreAndVerify(exported, from: source()))
    }

    func testRestoreThroughInMemoryDoublesExportsTheSameDocument() throws {
        try seedStore()
        let exported = try LocalBackup.document(from: source())

        // A second, empty store rebuilt purely from the document — the shape
        // of a device restoring a backup file.
        let freshQueue = try DialShotDatabaseFactory.makeQueue()
        try LocalBackup.restore(exported, into: freshQueue)
        let rebuilt = BackupSource(
            beans: SQLiteBeanRepository(writer: freshQueue),
            grinders: SQLiteGrinderRepository(writer: freshQueue),
            baskets: SQLiteBasketRepository(writer: freshQueue),
            recipes: SQLiteRecipeRepository(writer: freshQueue),
            shots: SQLiteShotRepository(writer: freshQueue),
            database: freshQueue
        )
        let reexported = try LocalBackup.document(from: rebuilt, exportedAt: exported.exportInfo.exportedAt)
        XCTAssertEqual(try BackupJSONCodec.encode(reexported), try BackupJSONCodec.encode(exported))
    }

    func testRestoreRollsBackCompletelyWhenAStatementFails() throws {
        try seedStore()
        let document = try LocalBackup.document(from: source())

        // Build a document that passes every Codable validation but breaks a
        // database foreign key mid-insert: the recipe points at a grinder id
        // the document never lists. restore() deletes every table FIRST, so
        // the only way the original data survives is if the transaction
        // rolls the deletes back too — that is the guarantee under test.
        guard let group = document.beanGroups.first, let recipe = group.recipes.first else {
            return XCTFail("fixture document incomplete")
        }
        let orphanSnapshot = try RecipeSnapshot(
            beanID: group.bean.id,
            grinderID: GrinderProfile.ID(rawValue: UUID()), // never in document.grinders
            basketID: recipe.snapshot.basketID,
            doseGrams: recipe.snapshot.doseGrams,
            targetYieldGrams: recipe.snapshot.targetYieldGrams,
            targetTimeSeconds: recipe.snapshot.targetTimeSeconds
        )
        let brokenGroup = BackupBeanGroup(
            bean: group.bean,
            activeRecipeID: group.activeRecipeID,
            recipes: [RecipeRecord(id: recipe.id, name: recipe.name, snapshot: orphanSnapshot, createdAt: recipe.createdAt)],
            shots: group.shots
        )
        let broken = BackupDocument(
            schemaVersion: document.schemaVersion,
            exportInfo: document.exportInfo,
            grinders: document.grinders,
            baskets: document.baskets,
            beanGroups: [brokenGroup],
            selectedBeanID: document.selectedBeanID
        )

        let beforeShots = try shots.count(beanID: nil)
        let beforeBeans = try beans.list().count
        XCTAssertThrowsError(try LocalBackup.restore(broken, into: queue))

        // Transaction rolled back: the original data is fully intact —
        // including the rows the restore had already deleted mid-write.
        XCTAssertEqual(try shots.count(beanID: nil), beforeShots)
        XCTAssertEqual(try beans.list().count, beforeBeans)
        XCTAssertNotNil(try shots.get(id: shotID))
        XCTAssertEqual(try recipes.active(for: beanID)?.id, recipeID)
        XCTAssertEqual(try recipes.selectedWorkspaceBeanID(), beanID)
    }
}
