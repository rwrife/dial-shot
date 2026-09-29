import Foundation

/// Presentation data for a saved attempt. A missing setting means the value was not recorded.
public struct HistoryShot: Identifiable, Sendable {
    public let attempt: ShotAttempt
    public let beanName: String
    public let grinderName: String
    public let grinderSetting: String?
    public var id: UUID { attempt.id }

    public init(attempt: ShotAttempt, beanName: String, grinderName: String, grinderSetting: String?) {
        self.attempt = attempt
        self.beanName = beanName
        self.grinderName = grinderName
        self.grinderSetting = grinderSetting
    }
}

public struct HistoryFilter: Sendable {
    public var beanQuery: String
    public var grinderQuery: String
    public var from: Date?
    public var through: Date?
    public var tasteVerdict: TasteVerdict?

    public init(beanQuery: String = "", grinderQuery: String = "", from: Date? = nil, through: Date? = nil, tasteVerdict: TasteVerdict? = nil) {
        self.beanQuery = beanQuery
        self.grinderQuery = grinderQuery
        self.from = from
        self.through = through
        self.tasteVerdict = tasteVerdict
    }
}

public enum ShotHistory {
    public static func filter(_ shots: [HistoryShot], using filter: HistoryFilter) -> [HistoryShot] {
        shots.filter { shot in
            let date = shot.attempt.createdAt
            return (filter.beanQuery.isEmpty || shot.beanName.localizedCaseInsensitiveContains(filter.beanQuery))
                && (filter.grinderQuery.isEmpty || shot.grinderName.localizedCaseInsensitiveContains(filter.grinderQuery))
                && (filter.from == nil || date >= filter.from!)
                && (filter.through == nil || date <= filter.through!)
                && (filter.tasteVerdict == nil || shot.attempt.observation.tasteVerdict == filter.tasteVerdict)
        }.sorted { lhs, rhs in
            lhs.attempt.createdAt == rhs.attempt.createdAt
                ? lhs.id.uuidString < rhs.id.uuidString
                : lhs.attempt.createdAt < rhs.attempt.createdAt
        }
    }
}

public enum ComparisonError: Error, Equatable {
    case exactlyTwoDistinctShotsRequired
    case differentBeans
}

public struct ShotComparison: Sendable {
    public let first: HistoryShot
    public let second: HistoryShot
    public let doseDifferent: Bool
    public let yieldDifferent: Bool
    public let timeDifferent: Bool
    /// Nil means settings cannot be compared because grinders differ or a historical setting is missing.
    public let grinderSettingDifferent: Bool?
    public let sensoryDifferent: Bool
    public let tasteDifferent: Bool
    public let notesDifferent: Bool
    public let flowDifferent: Bool

    public init(_ shots: [HistoryShot]) throws {
        guard shots.count == 2, shots[0].id != shots[1].id else {
            throw ComparisonError.exactlyTwoDistinctShotsRequired
        }
        guard shots[0].attempt.recipe.beanID == shots[1].attempt.recipe.beanID else {
            throw ComparisonError.differentBeans
        }
        first = shots[0]
        second = shots[1]
        doseDifferent = first.attempt.recipe.doseGrams != second.attempt.recipe.doseGrams
        yieldDifferent = first.attempt.measuredYieldGrams != second.attempt.measuredYieldGrams
        timeDifferent = first.attempt.elapsedSeconds != second.attempt.elapsedSeconds
        if first.attempt.recipe.grinderID == second.attempt.recipe.grinderID,
           let a = first.grinderSetting, let b = second.grinderSetting {
            grinderSettingDifferent = a != b
        } else {
            grinderSettingDifferent = nil
        }
        tasteDifferent = first.attempt.observation.tasteVerdict != second.attempt.observation.tasteVerdict
        notesDifferent = Set(first.attempt.observation.notes) != Set(second.attempt.observation.notes)
        flowDifferent = first.attempt.observation.flowVerdict != second.attempt.observation.flowVerdict
        sensoryDifferent = tasteDifferent || notesDifferent || flowDifferent
    }
}

public enum SensoryBalance: String, Equatable, Sendable {
    case underExtracted, balanced, overExtracted, unknown
}

public struct TrendPoint: Sendable {
    public let shotID: UUID
    public let createdAt: Date
    public let elapsedSeconds: Int
    public let sensoryBalance: SensoryBalance
}

public struct ShotTrend: Sendable {
    public let points: [TrendPoint]
    public let timeChangeSeconds: Int?

    public init(_ shots: [HistoryShot]) {
        points = ShotHistory.filter(shots, using: HistoryFilter()).map { shot in
            let observation = shot.attempt.observation
            let notes = Set(observation.notes)
            let balance: SensoryBalance
            switch observation.tasteVerdict {
            case .underExtracted where !notes.contains(.bitter) && !notes.contains(.astringent) && !notes.contains(.balanced): balance = .underExtracted
            case .overExtracted where !notes.contains(.sour) && !notes.contains(.balanced): balance = .overExtracted
            case .balanced where !notes.contains(.sour) && !notes.contains(.bitter) && !notes.contains(.astringent): balance = .balanced
            default: balance = .unknown
            }
            return TrendPoint(shotID: shot.id, createdAt: shot.attempt.createdAt, elapsedSeconds: shot.attempt.elapsedSeconds, sensoryBalance: balance)
        }
        if let first = points.first, let last = points.last, points.count > 1 {
            timeChangeSeconds = last.elapsedSeconds - first.elapsedSeconds
        } else {
            timeChangeSeconds = nil
        }
    }
}
