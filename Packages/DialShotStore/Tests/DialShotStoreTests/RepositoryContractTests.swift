import Foundation
import Testing
import DialShotKit
@testable import DialShotStore

/// Shared fixtures used by both the SQLite-backed and in-memory repository
/// contract tests so both implementations are proven against identical inputs.
enum RepositoryFixtures {
    static func makeBean(name: String = "Ethiopia Guji") -> BeanBag {
        BeanBag(name: name, roastDate: Date(timeIntervalSince1970: 1_700_000_000))
    }

    static func makeGrinder(name: String = "Niche Zero", setting: String = "12") -> GrinderProfile {
        GrinderProfile(name: name, settingLabel: setting)
    }

    static func makeBasket(name: String = "18g VST") -> BasketProfile {
        BasketProfile(name: name, nominalDoseGrams: Decimal(string: "18")!)
    }

    static func makeRecipeSnapshot(bean: BeanBag, grinder: GrinderProfile, basket: BasketProfile) throws -> RecipeSnapshot {
        try RecipeSnapshot(
            beanID: bean.id,
            grinderID: grinder.id,
            basketID: basket.id,
            doseGrams: Decimal(string: "18")!,
            targetYieldGrams: Decimal(string: "36")!,
            targetTimeSeconds: 30
        )
    }

    static func makeShot(recipe: RecipeSnapshot, taste: TasteVerdict? = .balanced, flow: FlowVerdict? = .onTarget, notes: [SensoryNote] = [.balanced]) throws -> ShotAttempt {
        try ShotAttempt(
            recipe: recipe,
            measuredYieldGrams: Decimal(string: "36")!,
            elapsedSeconds: 30,
            firstDropSeconds: 7,
            observation: SensoryObservation(tasteVerdict: taste, flowVerdict: flow, notes: notes)
        )
    }
}

/// Contract tests run against BOTH the SQLite-backed store and the in-memory
/// test double via `RepositoryContractSubject`, so a passing suite proves the
/// two implementations are behaviorally identical from the protocol's view.
struct RepositoryContractSubject {
    let beans: any BeanRepository
    let grinders: any GrinderRepository
    let baskets: any BasketRepository
    let recipes: any RecipeRepository
    let shots: any ShotRepository
}

func makeSQLiteSubject() throws -> RepositoryContractSubject {
    let queue = try DialShotDatabaseFactory.makeQueue()
    return RepositoryContractSubject(
        beans: SQLiteBeanRepository(writer: queue),
        grinders: SQLiteGrinderRepository(writer: queue),
        baskets: SQLiteBasketRepository(writer: queue),
        recipes: SQLiteRecipeRepository(writer: queue),
        shots: SQLiteShotRepository(writer: queue)
    )
}

func makeInMemorySubject() -> RepositoryContractSubject {
    RepositoryContractSubject(
        beans: InMemoryBeanRepository(),
        grinders: InMemoryGrinderRepository(),
        baskets: InMemoryBasketRepository(),
        recipes: InMemoryRecipeRepository(),
        shots: InMemoryShotRepository()
    )
}

@Suite("BeanRepository contract")
struct BeanRepositoryContractTests {
    @Test("save then get round-trips a bean bag", arguments: [true, false])
    func saveThenGet(useSQLite: Bool) throws {
        let subject = useSQLite ? try makeSQLiteSubject() : makeInMemorySubject()
        let bean = RepositoryFixtures.makeBean()

        try subject.beans.save(bean)
        let fetched = try subject.beans.get(id: bean.id)

        #expect(fetched == bean)
    }

    @Test("list returns all saved beans", arguments: [true, false])
    func listReturnsAll(useSQLite: Bool) throws {
        let subject = useSQLite ? try makeSQLiteSubject() : makeInMemorySubject()
        let first = RepositoryFixtures.makeBean(name: "Ethiopia Guji")
        let second = RepositoryFixtures.makeBean(name: "Kenya AA")

        try subject.beans.save(first)
        try subject.beans.save(second)
        let all = try subject.beans.list()

        #expect(Set(all.map(\.id)) == Set([first.id, second.id]))
    }

    @Test("get for missing id returns nil", arguments: [true, false])
    func getMissingReturnsNil(useSQLite: Bool) throws {
        let subject = useSQLite ? try makeSQLiteSubject() : makeInMemorySubject()

        let fetched = try subject.beans.get(id: BeanBag.ID())

        #expect(fetched == nil)
    }

    @Test("delete removes a bean bag", arguments: [true, false])
    func deleteRemoves(useSQLite: Bool) throws {
        let subject = useSQLite ? try makeSQLiteSubject() : makeInMemorySubject()
        let bean = RepositoryFixtures.makeBean()
        try subject.beans.save(bean)

        try subject.beans.delete(id: bean.id)

        #expect(try subject.beans.get(id: bean.id) == nil)
    }

    @Test("save is idempotent for the same id (upsert semantics)", arguments: [true, false])
    func saveUpserts(useSQLite: Bool) throws {
        let subject = useSQLite ? try makeSQLiteSubject() : makeInMemorySubject()
        let original = RepositoryFixtures.makeBean(name: "Original Name")
        try subject.beans.save(original)

        let renamed = BeanBag(id: original.id, name: "Renamed", roastDate: original.roastDate)
        try subject.beans.save(renamed)

        let fetched = try subject.beans.get(id: original.id)
        #expect(fetched?.name == "Renamed")
        #expect(try subject.beans.list().count == 1)
    }
}

@Suite("GrinderRepository contract")
struct GrinderRepositoryContractTests {
    @Test("save then get round-trips a grinder profile", arguments: [true, false])
    func saveThenGet(useSQLite: Bool) throws {
        let subject = useSQLite ? try makeSQLiteSubject() : makeInMemorySubject()
        let grinder = RepositoryFixtures.makeGrinder()

        try subject.grinders.save(grinder)
        let fetched = try subject.grinders.get(id: grinder.id)

        #expect(fetched == grinder)
    }

    @Test("list returns all saved grinders", arguments: [true, false])
    func listReturnsAll(useSQLite: Bool) throws {
        let subject = useSQLite ? try makeSQLiteSubject() : makeInMemorySubject()
        let first = RepositoryFixtures.makeGrinder(name: "Niche Zero", setting: "12")
        let second = RepositoryFixtures.makeGrinder(name: "DF64", setting: "16")

        try subject.grinders.save(first)
        try subject.grinders.save(second)

        #expect(Set(try subject.grinders.list().map(\.id)) == Set([first.id, second.id]))
    }

    @Test("delete removes a grinder profile", arguments: [true, false])
    func deleteRemoves(useSQLite: Bool) throws {
        let subject = useSQLite ? try makeSQLiteSubject() : makeInMemorySubject()
        let grinder = RepositoryFixtures.makeGrinder()
        try subject.grinders.save(grinder)

        try subject.grinders.delete(id: grinder.id)

        #expect(try subject.grinders.get(id: grinder.id) == nil)
    }
}

@Suite("BasketRepository contract")
struct BasketRepositoryContractTests {
    @Test("save then get round-trips a basket profile", arguments: [true, false])
    func saveThenGet(useSQLite: Bool) throws {
        let subject = useSQLite ? try makeSQLiteSubject() : makeInMemorySubject()
        let basket = RepositoryFixtures.makeBasket()

        try subject.baskets.save(basket)
        let fetched = try subject.baskets.get(id: basket.id)

        #expect(fetched == basket)
    }

    @Test("delete removes a basket profile", arguments: [true, false])
    func deleteRemoves(useSQLite: Bool) throws {
        let subject = useSQLite ? try makeSQLiteSubject() : makeInMemorySubject()
        let basket = RepositoryFixtures.makeBasket()
        try subject.baskets.save(basket)

        try subject.baskets.delete(id: basket.id)

        #expect(try subject.baskets.get(id: basket.id) == nil)
    }
}

@Suite("RecipeRepository contract")
struct RecipeRepositoryContractTests {
    private func makeSavedRecipe(subject: RepositoryContractSubject, beanName: String = "Ethiopia Guji") throws -> (RecipeRecord, BeanBag) {
        let bean = RepositoryFixtures.makeBean(name: beanName)
        let grinder = RepositoryFixtures.makeGrinder()
        let basket = RepositoryFixtures.makeBasket()
        try subject.beans.save(bean)
        try subject.grinders.save(grinder)
        try subject.baskets.save(basket)

        let snapshot = try RepositoryFixtures.makeRecipeSnapshot(bean: bean, grinder: grinder, basket: basket)
        let record = RecipeRecord(name: "Morning dial-in", snapshot: snapshot)
        try subject.recipes.save(record)
        return (record, bean)
    }

    @Test("save then get round-trips a recipe record", arguments: [true, false])
    func saveThenGet(useSQLite: Bool) throws {
        let subject = useSQLite ? try makeSQLiteSubject() : makeInMemorySubject()
        let (record, _) = try makeSavedRecipe(subject: subject)

        let fetched = try subject.recipes.get(id: record.id)

        #expect(fetched == record)
    }

    @Test("list filters by bean id", arguments: [true, false])
    func listFiltersByBean(useSQLite: Bool) throws {
        let subject = useSQLite ? try makeSQLiteSubject() : makeInMemorySubject()
        let (recordA, beanA) = try makeSavedRecipe(subject: subject, beanName: "Ethiopia Guji")
        let (_, beanB) = try makeSavedRecipe(subject: subject, beanName: "Kenya AA")

        let filtered = try subject.recipes.list(beanID: beanA.id)

        #expect(filtered.map(\.id) == [recordA.id])
        #expect(beanA.id != beanB.id)
    }

    @Test("list with nil bean id returns every recipe", arguments: [true, false])
    func listAllWhenNoFilter(useSQLite: Bool) throws {
        let subject = useSQLite ? try makeSQLiteSubject() : makeInMemorySubject()
        _ = try makeSavedRecipe(subject: subject, beanName: "Ethiopia Guji")
        _ = try makeSavedRecipe(subject: subject, beanName: "Kenya AA")

        #expect(try subject.recipes.list(beanID: nil).count == 2)
    }

    @Test("delete removes a recipe record", arguments: [true, false])
    func deleteRemoves(useSQLite: Bool) throws {
        let subject = useSQLite ? try makeSQLiteSubject() : makeInMemorySubject()
        let (record, _) = try makeSavedRecipe(subject: subject)

        try subject.recipes.delete(id: record.id)

        #expect(try subject.recipes.get(id: record.id) == nil)
    }
}

@Suite("ShotRepository contract")
struct ShotRepositoryContractTests {
    private func makeSetup(subject: RepositoryContractSubject) throws -> (BeanBag, RecipeSnapshot) {
        let bean = RepositoryFixtures.makeBean()
        let grinder = RepositoryFixtures.makeGrinder()
        let basket = RepositoryFixtures.makeBasket()
        try subject.beans.save(bean)
        try subject.grinders.save(grinder)
        try subject.baskets.save(basket)
        let snapshot = try RepositoryFixtures.makeRecipeSnapshot(bean: bean, grinder: grinder, basket: basket)
        return (bean, snapshot)
    }

    @Test("save then get round-trips a shot attempt with its computed suggestion", arguments: [true, false])
    func saveThenGet(useSQLite: Bool) throws {
        let subject = useSQLite ? try makeSQLiteSubject() : makeInMemorySubject()
        let (_, recipe) = try makeSetup(subject: subject)
        let shot = try RepositoryFixtures.makeShot(recipe: recipe, taste: .underExtracted, flow: .fast, notes: [.sour])

        try subject.shots.save(shot)
        let fetched = try subject.shots.get(id: shot.id)

        #expect(fetched?.attempt == shot)
        guard case .adjustment(let adjustment) = fetched?.suggestion else {
            Issue.record("expected a persisted adjustment suggestion")
            return
        }
        #expect(adjustment.action == .grindFiner)
        #expect(adjustment.rule == .underExtractedFastFlow)
    }

    @Test("an explicit suggestion overrides the derived one", arguments: [true, false])
    func explicitSuggestionOverridesDerived(useSQLite: Bool) throws {
        let subject = useSQLite ? try makeSQLiteSubject() : makeInMemorySubject()
        let (_, recipe) = try makeSetup(subject: subject)
        let shot = try RepositoryFixtures.makeShot(recipe: recipe, taste: .balanced, flow: .onTarget, notes: [.balanced])

        try subject.shots.save(shot, suggestion: .insufficientEvidence(reason: "manual override for test"))
        let fetched = try subject.shots.get(id: shot.id)

        #expect(fetched?.suggestion.isInsufficientEvidence == true)
    }

    @Test("list orders shots newest first and honors limit", arguments: [true, false])
    func listOrdersNewestFirstWithLimit(useSQLite: Bool) throws {
        let subject = useSQLite ? try makeSQLiteSubject() : makeInMemorySubject()
        let (bean, recipe) = try makeSetup(subject: subject)

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let shots = try (0..<3).map { offset -> ShotAttempt in
            try ShotAttempt(
                recipe: recipe,
                measuredYieldGrams: 36,
                elapsedSeconds: 30,
                firstDropSeconds: nil,
                observation: .balanced,
                createdAt: base.addingTimeInterval(Double(offset) * 60)
            )
        }
        for shot in shots {
            try subject.shots.save(shot)
        }

        let listed = try subject.shots.list(beanID: bean.id, limit: 2)

        #expect(listed.count == 2)
        #expect(listed.map(\.attempt.id) == [shots[2].id, shots[1].id])
    }

    @Test("count reflects saved shots for a bean", arguments: [true, false])
    func countReflectsSavedShots(useSQLite: Bool) throws {
        let subject = useSQLite ? try makeSQLiteSubject() : makeInMemorySubject()
        let (bean, recipe) = try makeSetup(subject: subject)
        try subject.shots.save(try RepositoryFixtures.makeShot(recipe: recipe))
        try subject.shots.save(try RepositoryFixtures.makeShot(recipe: recipe))

        #expect(try subject.shots.count(beanID: bean.id) == 2)
        #expect(try subject.shots.count(beanID: nil) == 2)
    }

    @Test("saving a changed attempt under an existing id is rejected as immutable", arguments: [true, false])
    func immutableAttemptCannotBeRewritten(useSQLite: Bool) throws {
        let subject = useSQLite ? try makeSQLiteSubject() : makeInMemorySubject()
        let (_, recipe) = try makeSetup(subject: subject)
        let original = try RepositoryFixtures.makeShot(recipe: recipe)
        try subject.shots.save(original)

        let changed = try ShotAttempt(
            id: original.id,
            recipe: recipe,
            measuredYieldGrams: 40,
            elapsedSeconds: 34,
            firstDropSeconds: original.firstDropSeconds,
            observation: original.observation,
            createdAt: original.createdAt
        )

        #expect(throws: DialShotStoreError.immutableShotConflict(original.id)) {
            try subject.shots.save(changed)
        }
        #expect(try subject.shots.get(id: original.id)?.attempt == original)
    }

    @Test("saving the identical immutable attempt is idempotent", arguments: [true, false])
    func identicalAttemptSaveIsIdempotent(useSQLite: Bool) throws {
        let subject = useSQLite ? try makeSQLiteSubject() : makeInMemorySubject()
        let (_, recipe) = try makeSetup(subject: subject)
        let shot = try RepositoryFixtures.makeShot(recipe: recipe)

        try subject.shots.save(shot)
        try subject.shots.save(shot)

        #expect(try subject.shots.count(beanID: nil) == 1)
        #expect(try subject.shots.get(id: shot.id)?.attempt == shot)
    }

    @Test("delete removes a shot attempt", arguments: [true, false])
    func deleteRemoves(useSQLite: Bool) throws {
        let subject = useSQLite ? try makeSQLiteSubject() : makeInMemorySubject()
        let (_, recipe) = try makeSetup(subject: subject)
        let shot = try RepositoryFixtures.makeShot(recipe: recipe)
        try subject.shots.save(shot)

        try subject.shots.delete(id: shot.id)

        #expect(try subject.shots.get(id: shot.id) == nil)
    }
}
