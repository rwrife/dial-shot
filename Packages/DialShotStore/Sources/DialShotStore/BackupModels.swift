import Foundation
import DialShotKit

/// Issue #7 — the versioned JSON backup document.
///
/// A `BackupDocument` is the complete, transportable contents of the local
/// store: every bean, grinder, basket, recipe (with its dialed-in flag), and
/// immutable shot record, plus the workspace's selected bean. It is
/// **versioned** so a future schema change can migrate old files instead of
/// silently mis-reading them.
///
/// Decimal quantities cross the JSON boundary as exact text (the same
/// `Decimal.description` encoding the SQLite store uses), *not* through the
/// default `Decimal` Codable conformance — the latter round-trips
/// non-terminating decimals through Double and would corrupt a stored ratio
/// or a user-entered dose. Dates cross as the exact
/// `timeIntervalSinceReferenceDate` double the SQLite store already persists,
/// which round-trips losslessly.
///
/// Decoding re-runs the validating domain initializers (RecipeSnapshot,
/// ShotAttempt, BrewRatio) and cross-checks stored ratio values against the
/// dose/yield pair, so a hostile file fails closed exactly like a hostile
/// database row would.
///
/// Foundation only — no GRDB, no UIKit, no networking — so the encode/
/// validate logic is testable anywhere and the zero-network gate stays
/// meaningful for everything the backup path touches.

/// Schema version of the JSON backup format.
public enum BackupSchemaVersion: Int, Codable, Equatable, Comparable, Sendable {
    case v1 = 1

    public static func < (lhs: BackupSchemaVersion, rhs: BackupSchemaVersion) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The only format version a restore may currently consume. A file with
    /// any other value is refused rather than guessed at.
    public static let supportedRestoreVersions: [BackupSchemaVersion] = [.v1]

    /// Decodes the raw integer directly so an unknown-but-readable version
    /// (e.g. from a future app build) reports `unsupportedSchemaVersion`
    /// instead of an opaque DecodingError from the synthesized conformance.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(Int.self)
        guard let version = BackupSchemaVersion(rawValue: raw) else {
            throw BackupValidationError.unsupportedSchemaVersion(raw)
        }
        self = version
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct BackupExportInfo: Codable, Equatable, Sendable {
    /// Bundle identifier of the app that produced the file, so a restore can
    /// refuse documents from a different product even if formats overlap.
    public let producerBundleID: String
    /// When the export ran (informational; never affects restore equality).
    public let exportedAt: Date
    /// Backup format version at the time of export.
    public let schemaVersion: BackupSchemaVersion

    public init(
        producerBundleID: String = BackupExportInfo.currentProducerBundleID,
        exportedAt: Date = Date(),
        schemaVersion: BackupSchemaVersion = .v1
    ) {
        self.producerBundleID = producerBundleID
        self.exportedAt = exportedAt
        self.schemaVersion = schemaVersion
    }

    public static let currentProducerBundleID = "com.infinityball.dialshot"
}

public enum BackupValidationError: Error, Codable, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case foreignProducer(bundleID: String)
    case inconsistentSchemaVersion(document: Int, metadata: Int)
    case duplicateID(kind: String, id: String)
    case danglingReference(kind: String, id: String, referenced: String, referencedID: String)
    case activeRecipeNotFound(beanID: String, recipeID: String)
    case corruptDecimal(String)
    case ratioMismatch(entity: String, stored: String, expected: String)
    case suggestionMismatch(shotID: String)
}

extension BackupValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let v):
            return "Backup file uses schema version \(v), which this app cannot restore."
        case .foreignProducer(let bundle):
            return "Backup file was produced by \(bundle), not this app."
        case .inconsistentSchemaVersion(let document, let metadata):
            return "Backup schema versions disagree (document \(document), metadata \(metadata))."
        case .duplicateID(let kind, let id):
            return "Backup file contains duplicate \(kind) id \(id)."
        case .danglingReference(let kind, let id, let referenced, let referencedID):
            return "\(kind) \(id) references \(referenced) \(referencedID) that is not in the backup."
        case .activeRecipeNotFound(let beanID, let recipeID):
            return "Bean \(beanID) is dialed in to recipe \(recipeID), which is not in the backup."
        case .corruptDecimal(let text):
            return "Backup file contains an invalid decimal value: \(text)."
        case .ratioMismatch(let entity, let stored, let expected):
            return "\(entity) stores ratio \(stored) that contradicts its dose/yield pair (\(expected))."
        case .suggestionMismatch(let id):
            return "Shot \(id) has a suggestion that contradicts its taste and flow evidence."
        }
    }
}

/// Transport form of a `RecipeRecord` with exact decimal text. Decoding
/// rebuilds the domain record through `RecipeSnapshot`'s validating
/// initializer and cross-checks the stored target-ratio value.
public struct BackupRecipePayload: Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String?
    public let beanID: UUID
    public let grinderID: UUID
    public let basketID: UUID
    public let doseGrams: String
    public let targetYieldGrams: String
    public let targetTimeSeconds: Int
    public let targetRatioValue: String
    public let createdAt: Double

    public init(_ record: RecipeRecord) {
        id = record.id
        name = record.name
        beanID = record.snapshot.beanID.rawValue
        grinderID = record.snapshot.grinderID.rawValue
        basketID = record.snapshot.basketID.rawValue
        doseGrams = record.snapshot.doseGrams.description
        targetYieldGrams = record.snapshot.targetYieldGrams.description
        targetTimeSeconds = record.snapshot.targetTimeSeconds
        targetRatioValue = record.snapshot.targetRatio.value.description
        createdAt = record.createdAt.timeIntervalSinceReferenceDate
    }

    public func toRecord() throws -> RecipeRecord {
        guard let dose = Decimal(string: doseGrams) else {
            throw BackupValidationError.corruptDecimal(doseGrams)
        }
        guard let yield = Decimal(string: targetYieldGrams) else {
            throw BackupValidationError.corruptDecimal(targetYieldGrams)
        }
        guard let storedRatio = Decimal(string: targetRatioValue) else {
            throw BackupValidationError.corruptDecimal(targetRatioValue)
        }
        let snapshot = try RecipeSnapshot(
            beanID: BeanBag.ID(rawValue: beanID),
            grinderID: GrinderProfile.ID(rawValue: grinderID),
            basketID: BasketProfile.ID(rawValue: basketID),
            doseGrams: dose,
            targetYieldGrams: yield,
            targetTimeSeconds: targetTimeSeconds
        )
        guard snapshot.targetRatio.value == storedRatio else {
            throw BackupValidationError.ratioMismatch(
                entity: "recipe \(id.uuidString)",
                stored: storedRatio.description,
                expected: snapshot.targetRatio.value.description
            )
        }
        return RecipeRecord(
            id: id,
            name: name,
            snapshot: snapshot,
            createdAt: Date(timeIntervalSinceReferenceDate: createdAt)
        )
    }
}

/// Transport form of a `ShotRecord`. Decoding re-runs `ShotAttempt`'s
/// validating initializer (negative timings and invalid first-drop fail
/// closed there) and cross-checks the stored brew-ratio value.
public struct BackupShotPayload: Codable, Equatable, Sendable {
    public let id: UUID
    public let beanID: UUID
    public let grinderID: UUID
    public let basketID: UUID
    public let doseGrams: String
    public let targetYieldGrams: String
    public let targetTimeSeconds: Int
    public let measuredYieldGrams: String
    public let brewRatioValue: String
    public let elapsedSeconds: Int
    public let firstDropSeconds: Int?
    public let tasteVerdict: TasteVerdict?
    public let flowVerdict: FlowVerdict?
    public let notes: [SensoryNote]
    public let suggestion: DialInSuggestion
    public let grinderSettingLabel: String?
    public let createdAt: Double

    public init(_ record: ShotRecord) {
        let attempt = record.attempt
        id = attempt.id
        beanID = attempt.recipe.beanID.rawValue
        grinderID = attempt.recipe.grinderID.rawValue
        basketID = attempt.recipe.basketID.rawValue
        doseGrams = attempt.recipe.doseGrams.description
        targetYieldGrams = attempt.recipe.targetYieldGrams.description
        targetTimeSeconds = attempt.recipe.targetTimeSeconds
        measuredYieldGrams = attempt.measuredYieldGrams.description
        brewRatioValue = attempt.brewRatio.value.description
        elapsedSeconds = attempt.elapsedSeconds
        firstDropSeconds = attempt.firstDropSeconds
        tasteVerdict = attempt.observation.tasteVerdict
        flowVerdict = attempt.observation.flowVerdict
        notes = attempt.observation.notes
        suggestion = record.suggestion
        grinderSettingLabel = record.grinderSettingLabel
        createdAt = attempt.createdAt.timeIntervalSinceReferenceDate
    }

    public func toRecord() throws -> ShotRecord {
        guard let dose = Decimal(string: doseGrams) else {
            throw BackupValidationError.corruptDecimal(doseGrams)
        }
        guard let yield = Decimal(string: targetYieldGrams) else {
            throw BackupValidationError.corruptDecimal(targetYieldGrams)
        }
        guard let measured = Decimal(string: measuredYieldGrams) else {
            throw BackupValidationError.corruptDecimal(measuredYieldGrams)
        }
        guard let storedRatio = Decimal(string: brewRatioValue) else {
            throw BackupValidationError.corruptDecimal(brewRatioValue)
        }
        let recipe = try RecipeSnapshot(
            beanID: BeanBag.ID(rawValue: beanID),
            grinderID: GrinderProfile.ID(rawValue: grinderID),
            basketID: BasketProfile.ID(rawValue: basketID),
            doseGrams: dose,
            targetYieldGrams: yield,
            targetTimeSeconds: targetTimeSeconds
        )
        let attempt = try ShotAttempt(
            id: id,
            recipe: recipe,
            measuredYieldGrams: measured,
            elapsedSeconds: elapsedSeconds,
            firstDropSeconds: firstDropSeconds,
            observation: SensoryObservation(tasteVerdict: tasteVerdict, flowVerdict: flowVerdict, notes: notes),
            createdAt: Date(timeIntervalSinceReferenceDate: createdAt)
        )
        guard attempt.brewRatio.value == storedRatio else {
            throw BackupValidationError.ratioMismatch(
                entity: "shot \(id.uuidString)",
                stored: storedRatio.description,
                expected: attempt.brewRatio.value.description
            )
        }
        // Rebuild adjustments through the rule table exactly like the store's
        // own decode: a file cannot smuggle a rationale that disagrees with
        // its rule.
        let canonicalSuggestion: DialInSuggestion
        if case .adjustment(let adjustment) = suggestion {
            // Existing immutable shots may carry an explicitly saved override.
            // Preserve that historic decision, but never import an action
            // whose own recorded rule explains a *different* action.
            let ruleAction: AdjustmentAction
            switch adjustment.rule {
            case .underExtractedFastFlow: ruleAction = .grindFiner
            case .underExtractedOnTargetFlow: ruleAction = .increaseYieldRatio
            case .overExtractedSlowFlow: ruleAction = .grindCoarser
            case .overExtractedOnTargetFlow: ruleAction = .decreaseYieldRatio
            }
            guard adjustment.action == ruleAction else {
                throw BackupValidationError.suggestionMismatch(shotID: id.uuidString)
            }
            canonicalSuggestion = .adjustment(Adjustment(action: adjustment.action, rule: adjustment.rule))
        } else {
            canonicalSuggestion = suggestion
        }
        return ShotRecord(attempt: attempt, suggestion: canonicalSuggestion, grinderSettingLabel: grinderSettingLabel)
    }
}

/// One bean and everything that hangs off it. Recipe snapshots are bound to
/// the bean id and shot attempts embed their recipe snapshot, so a bean group
/// is a self-contained slice. The custom decoder enforces referential closure
/// inside the group before a restore ever touches the database.
public struct BackupBeanGroup: Codable, Equatable, Sendable {
    public let bean: BeanBag
    public let activeRecipeID: UUID?
    public let recipes: [RecipeRecord]
    public let shots: [ShotRecord]

    public init(bean: BeanBag, activeRecipeID: UUID? = nil, recipes: [RecipeRecord] = [], shots: [ShotRecord] = []) {
        self.bean = bean
        self.activeRecipeID = activeRecipeID
        self.recipes = recipes
        self.shots = shots
    }

    private enum CodingKeys: String, CodingKey {
        case bean, activeRecipeID, recipes, shots
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bean = try container.decode(BeanBag.self, forKey: .bean)
        activeRecipeID = try container.decodeIfPresent(UUID.self, forKey: .activeRecipeID)
        let recipePayloads = try container.decode([BackupRecipePayload].self, forKey: .recipes)
        let shotPayloads = try container.decode([BackupShotPayload].self, forKey: .shots)
        recipes = try recipePayloads.map { try $0.toRecord() }
        shots = try shotPayloads.map { try $0.toRecord() }

        var recipeIDs = Set<String>()
        for recipe in recipes {
            guard recipeIDs.insert(recipe.id.uuidString).inserted else {
                throw BackupValidationError.duplicateID(kind: "recipe", id: recipe.id.uuidString)
            }
            guard recipe.snapshot.beanID == bean.id else {
                throw BackupValidationError.danglingReference(
                    kind: "recipe", id: recipe.id.uuidString,
                    referenced: "bean", referencedID: recipe.snapshot.beanID.rawValue.uuidString
                )
            }
        }
        if let activeRecipeID, !recipeIDs.contains(activeRecipeID.uuidString) {
            throw BackupValidationError.activeRecipeNotFound(
                beanID: bean.id.rawValue.uuidString, recipeID: activeRecipeID.uuidString
            )
        }
        var shotIDs = Set<String>()
        for shot in shots {
            guard shotIDs.insert(shot.id.uuidString).inserted else {
                throw BackupValidationError.duplicateID(kind: "shot", id: shot.id.uuidString)
            }
            guard shot.attempt.recipe.beanID == bean.id else {
                throw BackupValidationError.danglingReference(
                    kind: "shot", id: shot.id.uuidString,
                    referenced: "bean", referencedID: shot.attempt.recipe.beanID.rawValue.uuidString
                )
            }
        }
    }

    private func encodedRecipes() -> [BackupRecipePayload] { recipes.map(BackupRecipePayload.init) }
    private func encodedShots() -> [BackupShotPayload] { shots.map(BackupShotPayload.init) }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bean, forKey: .bean)
        try container.encodeIfPresent(activeRecipeID, forKey: .activeRecipeID)
        try container.encode(encodedRecipes(), forKey: .recipes)
        try container.encode(encodedShots(), forKey: .shots)
    }
}

/// The complete backup payload. The custom decoder validates schema version,
/// cross-collection referential closure (grinders/baskets exist for every
/// recipe and shot), and duplicate ids across the whole document.
public struct BackupDocument: Codable, Equatable, Sendable {
    public let schemaVersion: BackupSchemaVersion
    public let exportInfo: BackupExportInfo
    public let grinders: [GrinderProfile]
    public let baskets: [BasketProfile]
    public let beanGroups: [BackupBeanGroup]
    /// Bean the workspace had selected at export time; restore re-seeds it.
    public let selectedBeanID: BeanBag.ID?

    public init(
        schemaVersion: BackupSchemaVersion = .v1,
        exportInfo: BackupExportInfo = BackupExportInfo(),
        grinders: [GrinderProfile],
        baskets: [BasketProfile],
        beanGroups: [BackupBeanGroup],
        selectedBeanID: BeanBag.ID?
    ) {
        self.schemaVersion = schemaVersion
        self.exportInfo = exportInfo
        self.grinders = grinders
        self.baskets = baskets
        self.beanGroups = beanGroups
        self.selectedBeanID = selectedBeanID
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, exportInfo, grinders, baskets, beanGroups, selectedBeanID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(BackupSchemaVersion.self, forKey: .schemaVersion)
        exportInfo = try container.decode(BackupExportInfo.self, forKey: .exportInfo)
        grinders = try container.decode([GrinderProfile].self, forKey: .grinders)
        baskets = try container.decode([BasketProfile].self, forKey: .baskets)
        beanGroups = try container.decode([BackupBeanGroup].self, forKey: .beanGroups)
        selectedBeanID = try container.decodeIfPresent(BeanBag.ID.self, forKey: .selectedBeanID)

        guard BackupSchemaVersion.supportedRestoreVersions.contains(schemaVersion) else {
            throw BackupValidationError.unsupportedSchemaVersion(schemaVersion.rawValue)
        }
        guard exportInfo.schemaVersion == schemaVersion else {
            throw BackupValidationError.inconsistentSchemaVersion(
                document: schemaVersion.rawValue, metadata: exportInfo.schemaVersion.rawValue)
        }

        var grinderIDs = Set<String>()
        for grinder in grinders {
            guard grinderIDs.insert(grinder.id.rawValue.uuidString).inserted else {
                throw BackupValidationError.duplicateID(kind: "grinder", id: grinder.id.rawValue.uuidString)
            }
        }
        var basketIDs = Set<String>()
        for basket in baskets {
            guard basketIDs.insert(basket.id.rawValue.uuidString).inserted else {
                throw BackupValidationError.duplicateID(kind: "basket", id: basket.id.rawValue.uuidString)
            }
        }
        var beanIDs = Set<String>()
        for group in beanGroups {
            guard beanIDs.insert(group.bean.id.rawValue.uuidString).inserted else {
                throw BackupValidationError.duplicateID(kind: "bean", id: group.bean.id.rawValue.uuidString)
            }
        }
        var allRecipeIDs = Set<String>()
        var allShotIDs = Set<String>()
        for group in beanGroups {
            for recipe in group.recipes {
                let id = recipe.id.uuidString
                guard allRecipeIDs.insert(id).inserted else {
                    throw BackupValidationError.duplicateID(kind: "recipe", id: id)
                }
                guard grinderIDs.contains(recipe.snapshot.grinderID.rawValue.uuidString) else {
                    throw BackupValidationError.danglingReference(
                        kind: "recipe", id: id,
                        referenced: "grinder", referencedID: recipe.snapshot.grinderID.rawValue.uuidString
                    )
                }
                guard basketIDs.contains(recipe.snapshot.basketID.rawValue.uuidString) else {
                    throw BackupValidationError.danglingReference(
                        kind: "recipe", id: id,
                        referenced: "basket", referencedID: recipe.snapshot.basketID.rawValue.uuidString
                    )
                }
            }
            for shot in group.shots {
                let id = shot.id.uuidString
                guard allShotIDs.insert(id).inserted else {
                    throw BackupValidationError.duplicateID(kind: "shot", id: id)
                }
                guard grinderIDs.contains(shot.attempt.recipe.grinderID.rawValue.uuidString) else {
                    throw BackupValidationError.danglingReference(
                        kind: "shot", id: id,
                        referenced: "grinder", referencedID: shot.attempt.recipe.grinderID.rawValue.uuidString
                    )
                }
                guard basketIDs.contains(shot.attempt.recipe.basketID.rawValue.uuidString) else {
                    throw BackupValidationError.danglingReference(
                        kind: "shot", id: id,
                        referenced: "basket", referencedID: shot.attempt.recipe.basketID.rawValue.uuidString
                    )
                }
            }
        }
        if let selectedBeanID, !beanIDs.contains(selectedBeanID.rawValue.uuidString) {
            throw BackupValidationError.danglingReference(
                kind: "workspaceSelection", id: "selectedBeanId",
                referenced: "bean", referencedID: selectedBeanID.rawValue.uuidString
            )
        }
    }

    /// Counts per entity type — exactly what the restore preview shows
    /// before the user confirms a transactional replacement.
    public var entityCounts: BackupEntityCounts {
        BackupEntityCounts(
            beans: beanGroups.count,
            grinders: grinders.count,
            baskets: baskets.count,
            recipes: beanGroups.reduce(0) { $0 + $1.recipes.count },
            shots: beanGroups.reduce(0) { $0 + $1.shots.count }
        )
    }
}

public struct BackupEntityCounts: Codable, Equatable, Sendable {
    public let beans: Int
    public let grinders: Int
    public let baskets: Int
    public let recipes: Int
    public let shots: Int

    public init(beans: Int, grinders: Int, baskets: Int, recipes: Int, shots: Int) {
        self.beans = beans
        self.grinders = grinders
        self.baskets = baskets
        self.recipes = recipes
        self.shots = shots
    }

    public static let empty = BackupEntityCounts(beans: 0, grinders: 0, baskets: 0, recipes: 0, shots: 0)

    /// Human-readable preview line for the restore confirmation UI.
    public var previewSummary: String {
        func plural(_ n: Int, _ noun: String) -> String {
            "\(n) \(noun)\(n == 1 ? "" : "s")"
        }
        return [
            plural(beans, "bean"),
            plural(grinders, "grinder"),
            plural(baskets, "basket"),
            plural(recipes, "recipe"),
            plural(shots, "shot"),
        ].joined(separator: ", ")
    }
}

/// What a restore preview shows the user before confirmation: the declared
/// schema version, the producer, and entity counts. It is computed purely
/// from the validated document — no partial state is touched to produce it.
public struct BackupPreview: Equatable, Sendable {
    public let schemaVersion: BackupSchemaVersion
    public let producerBundleID: String
    public let entityCounts: BackupEntityCounts

    public init(schemaVersion: BackupSchemaVersion, producerBundleID: String, entityCounts: BackupEntityCounts) {
        self.schemaVersion = schemaVersion
        self.producerBundleID = producerBundleID
        self.entityCounts = entityCounts
    }
}
