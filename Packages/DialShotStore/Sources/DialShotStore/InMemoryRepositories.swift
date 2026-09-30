import Foundation
import DialShotKit

/// Thread-safe in-memory double of `BeanRepository` for fast tests and previews.
public final class InMemoryBeanRepository: BeanRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [BeanBag.ID: BeanBag] = [:]

    public init(initial: [BeanBag] = []) {
        for bean in initial {
            storage[bean.id] = bean
        }
    }

    public func save(_ bean: BeanBag) throws {
        lock.lock()
        defer { lock.unlock() }
        storage[bean.id] = bean
    }

    public func get(id: BeanBag.ID) throws -> BeanBag? {
        lock.lock()
        defer { lock.unlock() }
        return storage[id]
    }

    public func list() throws -> [BeanBag] {
        lock.lock()
        defer { lock.unlock() }
        return Array(storage.values).sorted { $0.name < $1.name }
    }

    public func delete(id: BeanBag.ID) throws {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: id)
    }
}

/// Thread-safe in-memory double of `GrinderRepository`.
public final class InMemoryGrinderRepository: GrinderRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [GrinderProfile.ID: GrinderProfile] = [:]

    public init(initial: [GrinderProfile] = []) {
        for item in initial {
            storage[item.id] = item
        }
    }

    public func save(_ grinder: GrinderProfile) throws {
        lock.lock()
        defer { lock.unlock() }
        storage[grinder.id] = grinder
    }

    public func get(id: GrinderProfile.ID) throws -> GrinderProfile? {
        lock.lock()
        defer { lock.unlock() }
        return storage[id]
    }

    public func list() throws -> [GrinderProfile] {
        lock.lock()
        defer { lock.unlock() }
        return Array(storage.values).sorted { $0.name < $1.name }
    }

    public func delete(id: GrinderProfile.ID) throws {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: id)
    }
}

/// Thread-safe in-memory double of `BasketRepository`.
public final class InMemoryBasketRepository: BasketRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [BasketProfile.ID: BasketProfile] = [:]

    public init(initial: [BasketProfile] = []) {
        for item in initial {
            storage[item.id] = item
        }
    }

    public func save(_ basket: BasketProfile) throws {
        lock.lock()
        defer { lock.unlock() }
        storage[basket.id] = basket
    }

    public func get(id: BasketProfile.ID) throws -> BasketProfile? {
        lock.lock()
        defer { lock.unlock() }
        return storage[id]
    }

    public func list() throws -> [BasketProfile] {
        lock.lock()
        defer { lock.unlock() }
        return Array(storage.values).sorted { $0.name < $1.name }
    }

    public func delete(id: BasketProfile.ID) throws {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: id)
    }
}

/// Thread-safe in-memory double of `RecipeRepository`.
public final class InMemoryRecipeRepository: RecipeRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [UUID: RecipeRecord] = [:]
    private var activeIDs: [BeanBag.ID: UUID] = [:]
    private var selectedWorkspaceBean: BeanBag.ID?


    public init(initial: [RecipeRecord] = []) {
        for item in initial {
            storage[item.id] = item
        }
    }

    public func save(_ recipe: RecipeRecord) throws {
        lock.lock()
        defer { lock.unlock() }
        storage[recipe.id] = recipe
    }

    public func get(id: UUID) throws -> RecipeRecord? {
        lock.lock()
        defer { lock.unlock() }
        return storage[id]
    }

    public func list(beanID: BeanBag.ID?) throws -> [RecipeRecord] {
        lock.lock()
        defer { lock.unlock() }
        let records = Array(storage.values)
        let filtered: [RecipeRecord]
        if let beanID {
            filtered = records.filter { $0.snapshot.beanID == beanID }
        } else {
            filtered = records
        }
        return filtered.sorted { $0.createdAt > $1.createdAt }
    }

    public func setActive(recipeID: UUID, for beanID: BeanBag.ID) throws {
        lock.lock(); defer { lock.unlock() }
        guard storage[recipeID]?.snapshot.beanID == beanID else { throw DialShotStoreError.missingReference("recipe") }
        activeIDs[beanID] = recipeID
    }

    public func active(for beanID: BeanBag.ID) throws -> RecipeRecord? {
        lock.lock(); defer { lock.unlock() }
        return activeIDs[beanID].flatMap { storage[$0] }
    }

    public func setSelectedWorkspaceBeanID(_ beanID: BeanBag.ID?) throws {
        lock.lock(); defer { lock.unlock() }
        selectedWorkspaceBean = beanID
    }

    public func selectedWorkspaceBeanID() throws -> BeanBag.ID? {
        lock.lock(); defer { lock.unlock() }
        return selectedWorkspaceBean
    }

    public func delete(id: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: id)
        activeIDs = activeIDs.filter { $0.value != id }
    }
}

/// Thread-safe in-memory double of `ShotRepository`.
public final class InMemoryShotRepository: ShotRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [UUID: ShotRecord] = [:]

    public init(initial: [ShotRecord] = []) {
        for item in initial {
            storage[item.id] = item
        }
    }

    public func save(_ attempt: ShotAttempt, suggestion: DialInSuggestion?) throws {
        let finalSuggestion = suggestion ?? DialInEngine.suggest(for: attempt)
        let record = ShotRecord(attempt: attempt, suggestion: finalSuggestion)
        lock.lock()
        defer { lock.unlock() }
        if let existing = storage[attempt.id] {
            guard existing == record else {
                throw DialShotStoreError.immutableShotConflict(attempt.id)
            }
            return
        }
        storage[attempt.id] = record
    }

    public func get(id: UUID) throws -> ShotRecord? {
        lock.lock()
        defer { lock.unlock() }
        return storage[id]
    }

    public func list(beanID: BeanBag.ID?, limit: Int?) throws -> [ShotRecord] {
        lock.lock()
        defer { lock.unlock() }
        var records = Array(storage.values)
        if let beanID {
            records = records.filter { $0.attempt.recipe.beanID == beanID }
        }
        records.sort { $0.attempt.createdAt > $1.attempt.createdAt }
        if let limit, limit > 0 {
            return Array(records.prefix(limit))
        }
        return records
    }

    public func delete(id: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: id)
    }

    public func count(beanID: BeanBag.ID?) throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        if let beanID {
            return storage.values.filter { $0.attempt.recipe.beanID == beanID }.count
        }
        return storage.count
    }
}
