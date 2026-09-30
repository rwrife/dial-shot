import Foundation
import DialShotKit

/// A saved, addressable recipe: a named wrapper around an immutable
/// `RecipeSnapshot` with its own identity for reference and history.
public struct RecipeRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String?
    public let snapshot: RecipeSnapshot
    public let createdAt: Date

    public init(id: UUID = UUID(), name: String? = nil, snapshot: RecipeSnapshot, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.snapshot = snapshot
        self.createdAt = createdAt
    }
}

/// A stored shot attempt together with the dial-in suggestion that was
/// derived from (or explicitly attached to) it at save time. Suggestions
/// are persisted alongside the immutable attempt so history never re-rolls
/// rationale when the rule table changes.
public struct ShotRecord: Codable, Equatable, Identifiable, Sendable {
    public let attempt: ShotAttempt
    public let suggestion: DialInSuggestion
    public let grinderSettingLabel: String?

    public var id: UUID { attempt.id }

    public init(attempt: ShotAttempt, suggestion: DialInSuggestion, grinderSettingLabel: String? = nil) {
        self.attempt = attempt
        self.suggestion = suggestion
        self.grinderSettingLabel = grinderSettingLabel
    }
}

/// Persistence boundary for bean bags.
public protocol BeanRepository: Sendable {
    func save(_ bean: BeanBag) throws
    func get(id: BeanBag.ID) throws -> BeanBag?
    func list() throws -> [BeanBag]
    func delete(id: BeanBag.ID) throws
}

/// Persistence boundary for grinder profiles. Grinder settings are
/// user-authored values scoped to a grinder; nothing here implies
/// cross-grinder equivalence.
public protocol GrinderRepository: Sendable {
    func save(_ grinder: GrinderProfile) throws
    func get(id: GrinderProfile.ID) throws -> GrinderProfile?
    func list() throws -> [GrinderProfile]
    func delete(id: GrinderProfile.ID) throws
}

/// Persistence boundary for basket profiles.
public protocol BasketRepository: Sendable {
    func save(_ basket: BasketProfile) throws
    func get(id: BasketProfile.ID) throws -> BasketProfile?
    func list() throws -> [BasketProfile]
    func delete(id: BasketProfile.ID) throws
}

/// Persistence boundary for saved recipes.
public protocol RecipeRepository: Sendable {
    func save(_ recipe: RecipeRecord) throws
    func get(id: UUID) throws -> RecipeRecord?
    func list(beanID: BeanBag.ID?) throws -> [RecipeRecord]
    func delete(id: UUID) throws
    func setActive(recipeID: UUID, for beanID: BeanBag.ID) throws
    func active(for beanID: BeanBag.ID) throws -> RecipeRecord?
    func setSelectedWorkspaceBeanID(_ beanID: BeanBag.ID?) throws
    func selectedWorkspaceBeanID() throws -> BeanBag.ID?
}

/// Persistence boundary for immutable shot attempts and their suggestions.
/// When `suggestion` is nil at save time, the deterministic
/// `DialInEngine.suggest(for:)` result is derived and stored.
public protocol ShotRepository: Sendable {
    func save(_ attempt: ShotAttempt, suggestion: DialInSuggestion?) throws
    func get(id: UUID) throws -> ShotRecord?
    func list(beanID: BeanBag.ID?, limit: Int?) throws -> [ShotRecord]
    func delete(id: UUID) throws
    func count(beanID: BeanBag.ID?) throws -> Int
}

extension ShotRepository {
    /// Saves the attempt with its deterministically derived suggestion.
    public func save(_ attempt: ShotAttempt) throws {
        try save(attempt, suggestion: nil)
    }
}
