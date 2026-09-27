import Foundation
import GRDB
import DialShotKit

enum StoreDecimalCodec {
    static func encode(_ value: Decimal) -> String {
        "\(value)"
    }

    static func decode(_ value: String) throws -> Decimal {
        guard let decimal = Decimal(string: value) else {
            throw DialShotStoreError.corruptDecimal(value)
        }
        return decimal
    }
}

enum StoreJSONCodec {
    static func encodeNotes(_ notes: [SensoryNote]) throws -> String {
        let data = try JSONEncoder().encode(notes.map(\.rawValue))
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    static func decodeNotes(_ json: String) throws -> [SensoryNote] {
        guard let data = json.data(using: .utf8) else { return [] }
        let rawValues = try JSONDecoder().decode([String].self, from: data)
        return rawValues.compactMap(SensoryNote.init(rawValue:))
    }
}

public enum DialShotStoreError: Error, Equatable, Sendable {
    case corruptDecimal(String)
    case corruptSuggestion(String)
    case missingReference(String)
    case immutableShotConflict(UUID)
}

/// SQLite-backed `BeanRepository`.
public final class SQLiteBeanRepository: BeanRepository, Sendable {
    private let writer: any DatabaseWriter

    public init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    public func save(_ bean: BeanBag) throws {
        try writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO bean_bag (id, name, roastDate, createdAt)
                    VALUES (:id, :name, :roastDate, :createdAt)
                    ON CONFLICT(id) DO UPDATE SET
                        name = excluded.name,
                        roastDate = excluded.roastDate
                """,
                arguments: [
                    "id": bean.id.rawValue.uuidString,
                    "name": bean.name,
                    "roastDate": bean.roastDate?.timeIntervalSinceReferenceDate,
                    "createdAt": Date().timeIntervalSinceReferenceDate,
                ]
            )
        }
    }

    public func get(id: BeanBag.ID) throws -> BeanBag? {
        try writer.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM bean_bag WHERE id = ?", arguments: [id.rawValue.uuidString]) else {
                return nil
            }
            return try Self.makeBean(from: row)
        }
    }

    public func list() throws -> [BeanBag] {
        try writer.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM bean_bag ORDER BY name")
            return try rows.map(Self.makeBean(from:))
        }
    }

    public func delete(id: BeanBag.ID) throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM bean_bag WHERE id = ?", arguments: [id.rawValue.uuidString])
        }
    }

    private static func makeBean(from row: Row) throws -> BeanBag {
        let idString: String = row["id"]
        let roastDateInterval: Double? = row["roastDate"]
        return BeanBag(
            id: BeanBag.ID(rawValue: UUID(uuidString: idString)!),
            name: row["name"],
            roastDate: roastDateInterval.map(Date.init(timeIntervalSinceReferenceDate:))
        )
    }
}

/// SQLite-backed `GrinderRepository`.
public final class SQLiteGrinderRepository: GrinderRepository, Sendable {
    private let writer: any DatabaseWriter

    public init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    public func save(_ grinder: GrinderProfile) throws {
        try writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO grinder_profile (id, name, settingLabel, createdAt)
                    VALUES (:id, :name, :settingLabel, :createdAt)
                    ON CONFLICT(id) DO UPDATE SET
                        name = excluded.name,
                        settingLabel = excluded.settingLabel
                """,
                arguments: [
                    "id": grinder.id.rawValue.uuidString,
                    "name": grinder.name,
                    "settingLabel": grinder.settingLabel,
                    "createdAt": Date().timeIntervalSinceReferenceDate,
                ]
            )
        }
    }

    public func get(id: GrinderProfile.ID) throws -> GrinderProfile? {
        try writer.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM grinder_profile WHERE id = ?", arguments: [id.rawValue.uuidString]) else {
                return nil
            }
            return Self.makeGrinder(from: row)
        }
    }

    public func list() throws -> [GrinderProfile] {
        try writer.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM grinder_profile ORDER BY name")
            return rows.map(Self.makeGrinder(from:))
        }
    }

    public func delete(id: GrinderProfile.ID) throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM grinder_profile WHERE id = ?", arguments: [id.rawValue.uuidString])
        }
    }

    private static func makeGrinder(from row: Row) -> GrinderProfile {
        let idString: String = row["id"]
        return GrinderProfile(
            id: GrinderProfile.ID(rawValue: UUID(uuidString: idString)!),
            name: row["name"],
            settingLabel: row["settingLabel"]
        )
    }
}

/// SQLite-backed `BasketRepository`.
public final class SQLiteBasketRepository: BasketRepository, Sendable {
    private let writer: any DatabaseWriter

    public init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    public func save(_ basket: BasketProfile) throws {
        try writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO basket_profile (id, name, nominalDoseGrams, createdAt)
                    VALUES (:id, :name, :nominalDoseGrams, :createdAt)
                    ON CONFLICT(id) DO UPDATE SET
                        name = excluded.name,
                        nominalDoseGrams = excluded.nominalDoseGrams
                """,
                arguments: [
                    "id": basket.id.rawValue.uuidString,
                    "name": basket.name,
                    "nominalDoseGrams": StoreDecimalCodec.encode(basket.nominalDoseGrams),
                    "createdAt": Date().timeIntervalSinceReferenceDate,
                ]
            )
        }
    }

    public func get(id: BasketProfile.ID) throws -> BasketProfile? {
        try writer.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM basket_profile WHERE id = ?", arguments: [id.rawValue.uuidString]) else {
                return nil
            }
            return try Self.makeBasket(from: row)
        }
    }

    public func list() throws -> [BasketProfile] {
        try writer.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM basket_profile ORDER BY name")
            return try rows.map(Self.makeBasket(from:))
        }
    }

    public func delete(id: BasketProfile.ID) throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM basket_profile WHERE id = ?", arguments: [id.rawValue.uuidString])
        }
    }

    private static func makeBasket(from row: Row) throws -> BasketProfile {
        let idString: String = row["id"]
        return BasketProfile(
            id: BasketProfile.ID(rawValue: UUID(uuidString: idString)!),
            name: row["name"],
            nominalDoseGrams: try StoreDecimalCodec.decode(row["nominalDoseGrams"])
        )
    }
}

/// SQLite-backed `RecipeRepository`.
public final class SQLiteRecipeRepository: RecipeRepository, Sendable {
    private let writer: any DatabaseWriter

    public init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    public func save(_ recipe: RecipeRecord) throws {
        try writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO recipe (
                        id, name, beanId, grinderId, basketId,
                        doseGrams, targetYieldGrams, targetTimeSeconds, createdAt
                    ) VALUES (
                        :id, :name, :beanId, :grinderId, :basketId,
                        :doseGrams, :targetYieldGrams, :targetTimeSeconds, :createdAt
                    )
                    ON CONFLICT(id) DO UPDATE SET
                        name = excluded.name,
                        doseGrams = excluded.doseGrams,
                        targetYieldGrams = excluded.targetYieldGrams,
                        targetTimeSeconds = excluded.targetTimeSeconds
                """,
                arguments: [
                    "id": recipe.id.uuidString,
                    "name": recipe.name,
                    "beanId": recipe.snapshot.beanID.rawValue.uuidString,
                    "grinderId": recipe.snapshot.grinderID.rawValue.uuidString,
                    "basketId": recipe.snapshot.basketID.rawValue.uuidString,
                    "doseGrams": StoreDecimalCodec.encode(recipe.snapshot.doseGrams),
                    "targetYieldGrams": StoreDecimalCodec.encode(recipe.snapshot.targetYieldGrams),
                    "targetTimeSeconds": recipe.snapshot.targetTimeSeconds,
                    "createdAt": recipe.createdAt.timeIntervalSinceReferenceDate,
                ]
            )
        }
    }

    public func get(id: UUID) throws -> RecipeRecord? {
        try writer.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM recipe WHERE id = ?", arguments: [id.uuidString]) else {
                return nil
            }
            return try Self.makeRecord(from: row)
        }
    }

    public func list(beanID: BeanBag.ID?) throws -> [RecipeRecord] {
        try writer.read { db in
            let rows: [Row]
            if let beanID {
                rows = try Row.fetchAll(
                    db,
                    sql: "SELECT * FROM recipe WHERE beanId = ? ORDER BY createdAt DESC",
                    arguments: [beanID.rawValue.uuidString]
                )
            } else {
                rows = try Row.fetchAll(db, sql: "SELECT * FROM recipe ORDER BY createdAt DESC")
            }
            return try rows.map(Self.makeRecord(from:))
        }
    }

    public func delete(id: UUID) throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM recipe WHERE id = ?", arguments: [id.uuidString])
        }
    }

    private static func makeRecord(from row: Row) throws -> RecipeRecord {
        let idString: String = row["id"]
        let beanIdString: String = row["beanId"]
        let grinderIdString: String = row["grinderId"]
        let basketIdString: String = row["basketId"]
        let createdInterval: Double = row["createdAt"]

        let snapshot = try RecipeSnapshot(
            beanID: BeanBag.ID(rawValue: UUID(uuidString: beanIdString)!),
            grinderID: GrinderProfile.ID(rawValue: UUID(uuidString: grinderIdString)!),
            basketID: BasketProfile.ID(rawValue: UUID(uuidString: basketIdString)!),
            doseGrams: try StoreDecimalCodec.decode(row["doseGrams"]),
            targetYieldGrams: try StoreDecimalCodec.decode(row["targetYieldGrams"]),
            targetTimeSeconds: row["targetTimeSeconds"]
        )

        return RecipeRecord(
            id: UUID(uuidString: idString)!,
            name: row["name"],
            snapshot: snapshot,
            createdAt: Date(timeIntervalSinceReferenceDate: createdInterval)
        )
    }
}

/// SQLite-backed `ShotRepository`. Suggestions are derived deterministically
/// at save time (unless explicitly provided) and stored alongside the
/// immutable attempt so the persisted rationale never changes retroactively.
public final class SQLiteShotRepository: ShotRepository, Sendable {
    private let writer: any DatabaseWriter

    public init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    public func save(_ attempt: ShotAttempt, suggestion: DialInSuggestion?) throws {
        let finalSuggestion = suggestion ?? DialInEngine.suggest(for: attempt)
        let incomingRecord = ShotRecord(attempt: attempt, suggestion: finalSuggestion)
        let (suggestionType, action, rule, rationale) = Self.encodeSuggestion(finalSuggestion)

        try writer.write { db in
            if let existingRow = try Row.fetchOne(db, sql: "SELECT * FROM shot_attempt WHERE id = ?", arguments: [attempt.id.uuidString]) {
                let existingRecord = try Self.makeRecord(from: existingRow)
                guard existingRecord == incomingRecord else {
                    throw DialShotStoreError.immutableShotConflict(attempt.id)
                }
                return
            }

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
                        createdAt
                    ) VALUES (
                        :id, :beanId, :grinderId, :basketId, :recipeId,
                        :doseGrams, :targetYieldGrams, :targetTimeSeconds,
                        :measuredYieldGrams, :brewRatioValue,
                        :elapsedSeconds, :firstDropSeconds,
                        :tasteVerdict, :flowVerdict, :sensoryNotesJson,
                        :suggestionType, :suggestedAdjustmentAction,
                        :suggestedAdjustmentRule, :suggestedAdjustmentRationale,
                        :createdAt
                    )
                """,
                arguments: [
                    "id": attempt.id.uuidString,
                    "beanId": attempt.recipe.beanID.rawValue.uuidString,
                    "grinderId": attempt.recipe.grinderID.rawValue.uuidString,
                    "basketId": attempt.recipe.basketID.rawValue.uuidString,
                    "recipeId": nil,
                    "doseGrams": StoreDecimalCodec.encode(attempt.recipe.doseGrams),
                    "targetYieldGrams": StoreDecimalCodec.encode(attempt.recipe.targetYieldGrams),
                    "targetTimeSeconds": attempt.recipe.targetTimeSeconds,
                    "measuredYieldGrams": StoreDecimalCodec.encode(attempt.measuredYieldGrams),
                    "brewRatioValue": StoreDecimalCodec.encode(attempt.brewRatio.value),
                    "elapsedSeconds": attempt.elapsedSeconds,
                    "firstDropSeconds": attempt.firstDropSeconds,
                    "tasteVerdict": attempt.observation.tasteVerdict?.rawValue,
                    "flowVerdict": attempt.observation.flowVerdict?.rawValue,
                    "sensoryNotesJson": try StoreJSONCodec.encodeNotes(attempt.observation.notes),
                    "suggestionType": suggestionType,
                    "suggestedAdjustmentAction": action,
                    "suggestedAdjustmentRule": rule,
                    "suggestedAdjustmentRationale": rationale,
                    "createdAt": attempt.createdAt.timeIntervalSinceReferenceDate,
                ]
            )
        }
    }

    public func get(id: UUID) throws -> ShotRecord? {
        try writer.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM shot_attempt WHERE id = ?", arguments: [id.uuidString]) else {
                return nil
            }
            return try Self.makeRecord(from: row)
        }
    }

    public func list(beanID: BeanBag.ID?, limit: Int?) throws -> [ShotRecord] {
        try writer.read { db in
            var sql = "SELECT * FROM shot_attempt"
            var arguments: [DatabaseValueConvertible] = []
            if let beanID {
                sql += " WHERE beanId = ?"
                arguments.append(beanID.rawValue.uuidString)
            }
            sql += " ORDER BY createdAt DESC"
            if let limit, limit > 0 {
                sql += " LIMIT ?"
                arguments.append(limit)
            }
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
            return try rows.map(Self.makeRecord(from:))
        }
    }

    public func delete(id: UUID) throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM shot_attempt WHERE id = ?", arguments: [id.uuidString])
        }
    }

    public func count(beanID: BeanBag.ID?) throws -> Int {
        try writer.read { db in
            if let beanID {
                return try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM shot_attempt WHERE beanId = ?",
                    arguments: [beanID.rawValue.uuidString]
                ) ?? 0
            }
            return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM shot_attempt") ?? 0
        }
    }

    private static func encodeSuggestion(_ suggestion: DialInSuggestion) -> (type: String, action: String?, rule: String?, rationale: String?) {
        switch suggestion {
        case .adjustment(let adjustment):
            return ("adjustment", adjustment.action.rawValue, adjustment.rule.rawValue, adjustment.rationale)
        case .noChangeRecommended:
            return ("noChange", nil, nil, nil)
        case .insufficientEvidence(let reason):
            return ("insufficientEvidence", nil, nil, reason)
        }
    }

    private static func decodeSuggestion(
        type: String,
        action: String?,
        rule: String?,
        rationale: String?
    ) throws -> DialInSuggestion {
        switch type {
        case "adjustment":
            guard
                let action, let actionValue = AdjustmentAction(rawValue: action),
                let rule, let ruleValue = AdjustmentRule(rawValue: rule)
            else {
                throw DialShotStoreError.corruptSuggestion(type)
            }
            return .adjustment(Adjustment(action: actionValue, rule: ruleValue))
        case "noChange":
            return .noChangeRecommended
        case "insufficientEvidence":
            return .insufficientEvidence(reason: rationale ?? "")
        default:
            throw DialShotStoreError.corruptSuggestion(type)
        }
    }

    private static func makeRecord(from row: Row) throws -> ShotRecord {
        let idString: String = row["id"]
        let beanIdString: String = row["beanId"]
        let grinderIdString: String = row["grinderId"]
        let basketIdString: String = row["basketId"]
        let createdInterval: Double = row["createdAt"]

        let recipe = try RecipeSnapshot(
            beanID: BeanBag.ID(rawValue: UUID(uuidString: beanIdString)!),
            grinderID: GrinderProfile.ID(rawValue: UUID(uuidString: grinderIdString)!),
            basketID: BasketProfile.ID(rawValue: UUID(uuidString: basketIdString)!),
            doseGrams: try StoreDecimalCodec.decode(row["doseGrams"]),
            targetYieldGrams: try StoreDecimalCodec.decode(row["targetYieldGrams"]),
            targetTimeSeconds: row["targetTimeSeconds"]
        )

        let tasteRaw: String? = row["tasteVerdict"]
        let flowRaw: String? = row["flowVerdict"]
        let notes = try StoreJSONCodec.decodeNotes(row["sensoryNotesJson"])

        let observation = SensoryObservation(
            tasteVerdict: tasteRaw.flatMap(TasteVerdict.init(rawValue:)),
            flowVerdict: flowRaw.flatMap(FlowVerdict.init(rawValue:)),
            notes: notes
        )

        let attempt = try ShotAttempt(
            id: UUID(uuidString: idString)!,
            recipe: recipe,
            measuredYieldGrams: try StoreDecimalCodec.decode(row["measuredYieldGrams"]),
            elapsedSeconds: row["elapsedSeconds"],
            firstDropSeconds: row["firstDropSeconds"],
            observation: observation,
            createdAt: Date(timeIntervalSinceReferenceDate: createdInterval)
        )

        let suggestion = try Self.decodeSuggestion(
            type: row["suggestionType"],
            action: row["suggestedAdjustmentAction"],
            rule: row["suggestedAdjustmentRule"],
            rationale: row["suggestedAdjustmentRationale"]
        )

        return ShotRecord(attempt: attempt, suggestion: suggestion)
    }
}
