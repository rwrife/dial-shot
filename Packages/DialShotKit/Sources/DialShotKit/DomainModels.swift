import Foundation

public struct BeanBag: Codable, Equatable, Identifiable, Sendable {
    public struct ID: Codable, Equatable, Hashable, Sendable {
        public let rawValue: UUID
        public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
    }

    public let id: ID
    public let name: String
    public let roastDate: Date?

    public init(id: ID = ID(), name: String, roastDate: Date? = nil) {
        self.id = id
        self.name = name
        self.roastDate = roastDate
    }
}

public struct GrinderProfile: Codable, Equatable, Identifiable, Sendable {
    public struct ID: Codable, Equatable, Hashable, Sendable {
        public let rawValue: UUID
        public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
    }

    public let id: ID
    public let name: String
    /// User-authored setting scoped to this grinder only.
    public let settingLabel: String

    public init(id: ID = ID(), name: String, settingLabel: String) {
        self.id = id
        self.name = name
        self.settingLabel = settingLabel
    }
}

public struct BasketProfile: Codable, Equatable, Identifiable, Sendable {
    public struct ID: Codable, Equatable, Hashable, Sendable {
        public let rawValue: UUID
        public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
    }

    public let id: ID
    public let name: String
    public let nominalDoseGrams: Decimal

    public init(id: ID = ID(), name: String, nominalDoseGrams: Decimal) {
        self.id = id
        self.name = name
        self.nominalDoseGrams = nominalDoseGrams
    }
}

public struct RecipeSnapshot: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case beanID
        case grinderID
        case basketID
        case doseGrams
        case targetYieldGrams
        case targetTimeSeconds
        case targetRatio
    }

    public let beanID: BeanBag.ID
    public let grinderID: GrinderProfile.ID
    public let basketID: BasketProfile.ID
    public let doseGrams: Decimal
    public let targetYieldGrams: Decimal
    public let targetTimeSeconds: Int
    public let targetRatio: BrewRatio

    public init(
        beanID: BeanBag.ID,
        grinderID: GrinderProfile.ID,
        basketID: BasketProfile.ID,
        doseGrams: Decimal,
        targetYieldGrams: Decimal,
        targetTimeSeconds: Int
    ) throws {
        self.beanID = beanID
        self.grinderID = grinderID
        self.basketID = basketID
        self.doseGrams = doseGrams
        self.targetYieldGrams = targetYieldGrams
        self.targetTimeSeconds = targetTimeSeconds
        targetRatio = try BrewRatio(doseGrams: doseGrams, yieldGrams: targetYieldGrams)
    }

    /// Decoding re-runs the validating initializer, so a payload cannot
    /// smuggle in a zero dose or a targetRatio inconsistent with its
    /// dose/yield pair (BrewRatio's own decoder verifies that pair).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            beanID: container.decode(BeanBag.ID.self, forKey: .beanID),
            grinderID: container.decode(GrinderProfile.ID.self, forKey: .grinderID),
            basketID: container.decode(BasketProfile.ID.self, forKey: .basketID),
            doseGrams: container.decode(Decimal.self, forKey: .doseGrams),
            targetYieldGrams: container.decode(Decimal.self, forKey: .targetYieldGrams),
            targetTimeSeconds: container.decode(Int.self, forKey: .targetTimeSeconds)
        )
        let storedRatio = try container.decode(BrewRatio.self, forKey: .targetRatio)
        if storedRatio != targetRatio {
            throw DecodingError.dataCorruptedError(
                forKey: .targetRatio,
                in: container,
                debugDescription: "RecipeSnapshot targetRatio does not match its dose/yield pair"
            )
        }
    }
}

public enum TasteVerdict: String, Codable, Equatable, Sendable {
    case underExtracted
    case balanced
    case overExtracted
}

public enum FlowVerdict: String, Codable, Equatable, Sendable {
    case fast
    case onTarget
    case slow
}

public enum SensoryNote: String, Codable, Equatable, Hashable, Sendable {
    case sour
    case balanced
    case bitter
    case astringent
    case thin
    case channeling
}

public struct SensoryObservation: Codable, Equatable, Sendable {
    public let tasteVerdict: TasteVerdict?
    public let flowVerdict: FlowVerdict?
    public let notes: [SensoryNote]

    public init(tasteVerdict: TasteVerdict?, flowVerdict: FlowVerdict?, notes: [SensoryNote]) {
        self.tasteVerdict = tasteVerdict
        self.flowVerdict = flowVerdict
        self.notes = notes
    }

    public static let balanced = SensoryObservation(
        tasteVerdict: .balanced,
        flowVerdict: .onTarget,
        notes: [.balanced]
    )
}

public enum ShotAttemptError: Error, Codable, Equatable, Sendable {
    case negativeElapsedSeconds
    case invalidFirstDrop
}

public struct ShotAttempt: Codable, Equatable, Sendable {
    public let id: UUID
    public let recipe: RecipeSnapshot
    public let measuredYieldGrams: Decimal
    public let brewRatio: BrewRatio
    public let elapsedSeconds: Int
    public let firstDropSeconds: Int?
    public let observation: SensoryObservation
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        recipe: RecipeSnapshot,
        measuredYieldGrams: Decimal,
        elapsedSeconds: Int,
        firstDropSeconds: Int?,
        observation: SensoryObservation,
        createdAt: Date = Date()
    ) throws {
        guard elapsedSeconds >= 0 else { throw ShotAttemptError.negativeElapsedSeconds }
        if let firstDropSeconds {
            guard firstDropSeconds >= 0, firstDropSeconds <= elapsedSeconds else {
                throw ShotAttemptError.invalidFirstDrop
            }
        }

        self.id = id
        self.recipe = recipe
        self.measuredYieldGrams = measuredYieldGrams
        brewRatio = try BrewRatio(doseGrams: recipe.doseGrams, yieldGrams: measuredYieldGrams)
        self.elapsedSeconds = elapsedSeconds
        self.firstDropSeconds = firstDropSeconds
        self.observation = observation
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case recipe
        case measuredYieldGrams
        case brewRatio
        case elapsedSeconds
        case firstDropSeconds
        case observation
        case createdAt
    }

    /// Decoding re-runs the validating initializer so hostile payloads
    /// (negative timings, first-drop after stop, stored ratio mismatched
    /// against dose/yield) fail closed instead of restoring broken truth.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            recipe: container.decode(RecipeSnapshot.self, forKey: .recipe),
            measuredYieldGrams: container.decode(Decimal.self, forKey: .measuredYieldGrams),
            elapsedSeconds: container.decode(Int.self, forKey: .elapsedSeconds),
            firstDropSeconds: container.decodeIfPresent(Int.self, forKey: .firstDropSeconds),
            observation: container.decode(SensoryObservation.self, forKey: .observation),
            createdAt: container.decode(Date.self, forKey: .createdAt)
        )
        let storedRatio = try container.decode(BrewRatio.self, forKey: .brewRatio)
        if storedRatio != brewRatio {
            throw DecodingError.dataCorruptedError(
                forKey: .brewRatio,
                in: container,
                debugDescription: "ShotAttempt brewRatio does not match its dose/yield pair"
            )
        }
    }
}
