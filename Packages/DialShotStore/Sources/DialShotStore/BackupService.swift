import Foundation
import GRDB
import DialShotKit

/// Issue #7 — building and applying the versioned JSON backup.
///
/// `BackupJSONCodec` is the pure encode/validate boundary. `LocalBackup` is
/// the store-side service: it assembles a `BackupDocument` from the
/// repository protocols and applies a restore as one GRDB write transaction —
/// every table is cleared and repopulated inside a single transaction, so a
/// failed restore leaves the previous data fully intact (no partial
/// replacement is ever observable).
public enum BackupJSONCodec {
    /// Deterministic text form: sorted keys and pretty printing keep two
    /// exports of identical data byte-identical apart from `exportedAt`,
    /// which makes export diffs reviewable and tests exact.
    public static func encode(_ document: BackupDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(document)
    }

    /// Decodes and validates a backup file. Throws `BackupValidationError`
    /// for structural violations (unsupported schema version, dangling or
    /// duplicate ids, contradicted ratio values) and `DecodingError` for
    /// malformed payloads — including any entity payload that violates the
    /// domain validators (BrewRatio mismatch, invalid timings).
    public static func decode(_ data: Data) throws -> BackupDocument {
        try JSONDecoder().decode(BackupDocument.self, from: data)
    }

    /// Decodes a file and additionally enforces the product identity — the
    /// only path the restore flow may use. A document produced by a
    /// different app is refused even if structurally valid.
    public static func decodedForRestore(_ data: Data) throws -> BackupDocument {
        let document = try decode(data)
        guard document.exportInfo.producerBundleID == BackupExportInfo.currentProducerBundleID else {
            throw BackupValidationError.foreignProducer(bundleID: document.exportInfo.producerBundleID)
        }
        return document
    }

    /// Preview for the restore confirmation UI: what the user is about to
    /// replace, computed entirely from the validated file — nothing in the
    /// database is touched to produce it.
    public static func preview(_ data: Data) throws -> BackupPreview {
        let document = try decodedForRestore(data)
        return BackupPreview(
            schemaVersion: document.schemaVersion,
            producerBundleID: document.exportInfo.producerBundleID,
            entityCounts: document.entityCounts
        )
    }
}

/// Everything `LocalBackup` needs from one local store. Bundling
/// repositories behind plain protocol existentials keeps the service
/// testable against the in-memory doubles and against the SQLite store
/// alike.
public struct BackupSource: Sendable {
    public let beans: any BeanRepository
    public let grinders: any GrinderRepository
    public let baskets: any BasketRepository
    public let recipes: any RecipeRepository
    public let shots: any ShotRepository
    public let database: any DatabaseWriter

    public init(
        beans: any BeanRepository,
        grinders: any GrinderRepository,
        baskets: any BasketRepository,
        recipes: any RecipeRepository,
        shots: any ShotRepository,
        database: any DatabaseWriter
    ) {
        self.beans = beans
        self.grinders = grinders
        self.baskets = baskets
        self.recipes = recipes
        self.shots = shots
        self.database = database
    }
}

public enum LocalBackup {
    /// Snapshots the whole database into a versioned document. Repository
    /// ordering is deterministic, so two exports of the same data produce
    /// identical bytes apart from `exportedAt`.
    public static func document(from source: BackupSource, exportedAt: Date = Date()) throws -> BackupDocument {
        let beans = try source.beans.list()
        let grinders = try source.grinders.list()
        let baskets = try source.baskets.list()
        let allRecipes = try source.recipes.list(beanID: nil)

        var groups: [BackupBeanGroup] = []
        for bean in beans {
            let beanRecipes = allRecipes.filter { $0.snapshot.beanID == bean.id }
            let activeID = try source.recipes.active(for: bean.id)?.id
            let beanShots = try source.shots.list(beanID: bean.id, limit: nil)
            groups.append(BackupBeanGroup(bean: bean, activeRecipeID: activeID, recipes: beanRecipes, shots: beanShots))
        }

        return BackupDocument(
            schemaVersion: .v1,
            exportInfo: BackupExportInfo(exportedAt: exportedAt, schemaVersion: .v1),
            grinders: grinders,
            baskets: baskets,
            beanGroups: groups,
            selectedBeanID: try source.recipes.selectedWorkspaceBeanID()
        )
    }

    /// Applies a validated document as a full replacement of the local data
    /// in one write transaction: every table is cleared and repopulated from
    /// the document. If any insert fails (a foreign-key violation from a
    /// dangling reference, a domain validator rejecting a payload mid-way),
    /// the transaction rolls back and the original data is untouched.
    public static func restore(_ document: BackupDocument, into database: any DatabaseWriter) throws {
        // Even direct callers must pass the same validation as the Files UI.
        let validated = try BackupJSONCodec.decodedForRestore(BackupJSONCodec.encode(document))
        try database.write { db in
            // Clear order matters only for readability; SQLite checks
            // deferred foreign keys per statement, and all parents are
            // re-inserted before any child.
            try db.execute(sql: "DELETE FROM shot_attempt")
            try db.execute(sql: "DELETE FROM bean_active_recipe")
            try db.execute(sql: "DELETE FROM app_workspace_state")
            try db.execute(sql: "DELETE FROM recipe")
            try db.execute(sql: "DELETE FROM bean_bag")
            try db.execute(sql: "DELETE FROM grinder_profile")
            try db.execute(sql: "DELETE FROM basket_profile")

            // Insertion order is dependency-safe: beans first, then their
            // parents/grinders and baskets, then recipes and shots. A
            // document that fails validation later therefore never leaves a
            // bean referencing a missing grinder behind.
            for group in validated.beanGroups {
                try db.execute(
                    sql: "INSERT INTO bean_bag (id, name, roastDate, createdAt) VALUES (?, ?, ?, ?)",
                    arguments: [
                        group.bean.id.rawValue.uuidString,
                        group.bean.name,
                        group.bean.roastDate?.timeIntervalSinceReferenceDate,
                        Date().timeIntervalSinceReferenceDate,
                    ]
                )
            }
            for grinder in validated.grinders {
                try db.execute(
                    sql: "INSERT INTO grinder_profile (id, name, settingLabel, createdAt) VALUES (?, ?, ?, ?)",
                    arguments: [grinder.id.rawValue.uuidString, grinder.name, grinder.settingLabel, Date().timeIntervalSinceReferenceDate]
                )
            }
            for basket in validated.baskets {
                try db.execute(
                    sql: "INSERT INTO basket_profile (id, name, nominalDoseGrams, createdAt) VALUES (?, ?, ?, ?)",
                    arguments: [basket.id.rawValue.uuidString, basket.name, basket.nominalDoseGrams.description, Date().timeIntervalSinceReferenceDate]
                )
            }
            for group in validated.beanGroups {
                for recipe in group.recipes {
                    try db.execute(
                        sql: """
                            INSERT INTO recipe (id, name, beanId, grinderId, basketId, doseGrams, targetYieldGrams, targetTimeSeconds, createdAt)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                        arguments: [
                            recipe.id.uuidString,
                            recipe.name,
                            group.bean.id.rawValue.uuidString,
                            recipe.snapshot.grinderID.rawValue.uuidString,
                            recipe.snapshot.basketID.rawValue.uuidString,
                            recipe.snapshot.doseGrams.description,
                            recipe.snapshot.targetYieldGrams.description,
                            recipe.snapshot.targetTimeSeconds,
                            recipe.createdAt.timeIntervalSinceReferenceDate,
                        ]
                    )
                }
                if let activeRecipeID = group.activeRecipeID {
                    try db.execute(
                        sql: "INSERT INTO bean_active_recipe (beanId, recipeId) VALUES (?, ?)",
                        arguments: [group.bean.id.rawValue.uuidString, activeRecipeID.uuidString]
                    )
                }
                for shot in group.shots {
                    let attempt = shot.attempt
                    let (suggestionType, action, rule, rationale) = Self.encodeSuggestion(shot.suggestion)
                    try db.execute(
                        sql: """
                            INSERT INTO shot_attempt (
                                id, beanId, grinderId, basketId, recipeId,
                                doseGrams, targetYieldGrams, targetTimeSeconds,
                                measuredYieldGrams, brewRatioValue,
                                elapsedSeconds, firstDropSeconds,
                                tasteVerdict, flowVerdict, sensoryNotesJson,
                                suggestionType, suggestedAdjustmentAction,
                                suggestedAdjustmentRule, suggestedAdjustmentRationale,
                                createdAt, grinderSettingLabel
                            ) VALUES (
                                :id, :beanId, :grinderId, :basketId, :recipeId,
                                :doseGrams, :targetYieldGrams, :targetTimeSeconds,
                                :measuredYieldGrams, :brewRatioValue,
                                :elapsedSeconds, :firstDropSeconds,
                                :tasteVerdict, :flowVerdict, :sensoryNotesJson,
                                :suggestionType, :suggestedAdjustmentAction,
                                :suggestedAdjustmentRule, :suggestedAdjustmentRationale,
                                :createdAt, :grinderSettingLabel
                            )
                        """,
                        arguments: [
                            "id": attempt.id.uuidString,
                            "beanId": attempt.recipe.beanID.rawValue.uuidString,
                            "grinderId": attempt.recipe.grinderID.rawValue.uuidString,
                            "basketId": attempt.recipe.basketID.rawValue.uuidString,
                            "recipeId": nil as String?,
                            "doseGrams": attempt.recipe.doseGrams.description,
                            "targetYieldGrams": attempt.recipe.targetYieldGrams.description,
                            "targetTimeSeconds": attempt.recipe.targetTimeSeconds,
                            "measuredYieldGrams": attempt.measuredYieldGrams.description,
                            "brewRatioValue": attempt.brewRatio.value.description,
                            "elapsedSeconds": attempt.elapsedSeconds,
                            "firstDropSeconds": attempt.firstDropSeconds,
                            "tasteVerdict": attempt.observation.tasteVerdict?.rawValue,
                            "flowVerdict": attempt.observation.flowVerdict?.rawValue,
                            "sensoryNotesJson": try Self.encodeNotes(attempt.observation.notes),
                            "suggestionType": suggestionType,
                            "suggestedAdjustmentAction": action,
                            "suggestedAdjustmentRule": rule,
                            "suggestedAdjustmentRationale": rationale,
                            "createdAt": attempt.createdAt.timeIntervalSinceReferenceDate,
                            "grinderSettingLabel": shot.grinderSettingLabel,
                        ]
                    )
                }
            }
            if let selectedBeanID = validated.selectedBeanID {
                try db.execute(
                    sql: "INSERT INTO app_workspace_state (key, value) VALUES ('selectedBeanId', ?)",
                    arguments: [selectedBeanID.rawValue.uuidString]
                )
            }
        }
    }

    /// First rehearse the complete restore in a disposable SQLite database
    /// and verify its re-export. Only after that succeeds do we replace the
    /// live store in one transaction. A verification error never happens
    /// *after* a committed replacement has already destroyed the prior data.
    public static func restoreAndVerify(_ document: BackupDocument, from source: BackupSource) throws {
        let rehearsal = try DialShotDatabaseFactory.makeQueue()
        try restore(document, into: rehearsal)
        let rehearsalSource = BackupSource(
            beans: SQLiteBeanRepository(writer: rehearsal),
            grinders: SQLiteGrinderRepository(writer: rehearsal),
            baskets: SQLiteBasketRepository(writer: rehearsal),
            recipes: SQLiteRecipeRepository(writer: rehearsal),
            shots: SQLiteShotRepository(writer: rehearsal),
            database: rehearsal
        )
        let reexport = try LocalBackup.document(from: rehearsalSource, exportedAt: document.exportInfo.exportedAt)
        guard normalize(reexport, exportInfo: document.exportInfo) == normalize(document, exportInfo: document.exportInfo) else {
            throw DialShotStoreError.backupRoundTripMismatch
        }
        try restore(document, into: source.database)
    }

    /// Canonical ordering for round-trip equality: a restore document from a
    /// foreign editor could arrive in any order, so identity is compared on
    /// sorted collections rather than wire order.
    private static func normalize(_ document: BackupDocument, exportInfo: BackupExportInfo) -> BackupDocument {
        let groups = document.beanGroups
            .sorted { ($0.bean.name, $0.bean.id.rawValue.uuidString) < ($1.bean.name, $1.bean.id.rawValue.uuidString) }
            .map { group in
                BackupBeanGroup(
                    bean: group.bean,
                    activeRecipeID: group.activeRecipeID,
                    recipes: group.recipes.sorted { $0.id.uuidString < $1.id.uuidString },
                    shots: group.shots.sorted { $0.id.uuidString < $1.id.uuidString }
                )
            }
        return BackupDocument(
            schemaVersion: document.schemaVersion,
            exportInfo: exportInfo,
            grinders: document.grinders.sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString },
            baskets: document.baskets.sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString },
            beanGroups: groups,
            selectedBeanID: document.selectedBeanID
        )
    }

    private static func encodeSuggestion(_ suggestion: DialInSuggestion) -> (String, String?, String?, String?) {
        switch suggestion {
        case .adjustment(let adjustment):
            return ("adjustment", adjustment.action.rawValue, adjustment.rule.rawValue, adjustment.rationale)
        case .noChangeRecommended:
            return ("noChange", nil, nil, nil)
        case .insufficientEvidence(let reason):
            return ("insufficientEvidence", nil, nil, reason)
        }
    }

    private static func encodeNotes(_ notes: [SensoryNote]) throws -> String {
        let data = try JSONEncoder().encode(notes.map(\.rawValue))
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
