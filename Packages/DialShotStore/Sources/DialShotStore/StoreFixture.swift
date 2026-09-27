import Foundation
import GRDB
import DialShotKit

/// Deterministic, fixed-identity seed dataset for the committed regression
/// fixture database (`Tests/DialShotStoreTests/Fixtures/v1_fixture.sqlite`).
///
/// The seed is pure (fixed UUIDs and timestamps, no `Date()` or `UUID()`
/// randomness) so regenerating the fixture is byte-reproducible and so tests
/// can assert the exact persisted values the fixture is expected to carry.
public enum StoreFixture {
    public static let beanEthiopia = BeanBag(
        id: BeanBag.ID(rawValue: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!),
        name: "Ethiopia Guji Natural",
        roastDate: fixedDate(day: 3, hour: 9)
    )

    public static let beanColombia = BeanBag(
        id: BeanBag.ID(rawValue: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!),
        name: "Colombia Huila Washed",
        roastDate: fixedDate(day: 10, hour: 14)
    )

    public static let grinderNiche = GrinderProfile(
        id: GrinderProfile.ID(rawValue: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!),
        name: "Niche Zero",
        settingLabel: "2.4"
    )

    public static let basketVST18 = BasketProfile(
        id: BasketProfile.ID(rawValue: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!),
        name: "VST 18g",
        nominalDoseGrams: 18
    )

    public static let recipeEthiopia = RecipeRecord(
        id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
        name: "Ethiopia morning dial-in",
        snapshot: try! RecipeSnapshot(
            beanID: beanEthiopia.id,
            grinderID: grinderNiche.id,
            basketID: basketVST18.id,
            doseGrams: 18,
            targetYieldGrams: 36,
            targetTimeSeconds: 30
        ),
        createdAt: fixedDate(day: 12, hour: 8)
    )

    public static let recipeColombia = RecipeRecord(
        id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
        name: "Colombia baseline",
        snapshot: try! RecipeSnapshot(
            beanID: beanColombia.id,
            grinderID: grinderNiche.id,
            basketID: basketVST18.id,
            doseGrams: 18,
            targetYieldGrams: 40,
            targetTimeSeconds: 30
        ),
        createdAt: fixedDate(day: 12, hour: 9)
    )

    /// Under-extracted (sour) + fast flow on the Ethiopia recipe (drives a "grind finer" adjustment).
    public static let shotSourFast = try! ShotAttempt(
        id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
        recipe: recipeEthiopia.snapshot,
        measuredYieldGrams: 36,
        elapsedSeconds: 24,
        firstDropSeconds: 5,
        observation: SensoryObservation(tasteVerdict: .underExtracted, flowVerdict: .fast, notes: [.sour]),
        createdAt: fixedDate(day: 12, hour: 10)
    )

    /// Balanced + on-target shot (drives a "no change" verdict).
    public static let shotBalanced = try! ShotAttempt(
        id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
        recipe: recipeEthiopia.snapshot,
        measuredYieldGrams: 36,
        elapsedSeconds: 29,
        firstDropSeconds: 7,
        observation: .balanced,
        createdAt: fixedDate(day: 12, hour: 11)
    )

    /// Over-extracted (bitter) + slow flow on the Colombia recipe (drives a "grind coarser" adjustment).
    public static let shotBitterSlow = try! ShotAttempt(
        id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
        recipe: recipeColombia.snapshot,
        measuredYieldGrams: 40,
        elapsedSeconds: 34,
        firstDropSeconds: 9,
        observation: SensoryObservation(tasteVerdict: .overExtracted, flowVerdict: .slow, notes: [.bitter]),
        createdAt: fixedDate(day: 12, hour: 12)
    )

    /// Conflicting evidence shot (under-extracted taste but slow flow) — exercises the
    /// explicit unknown state rather than a guess.
    public static let shotConflicting = try! ShotAttempt(
        id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
        recipe: recipeColombia.snapshot,
        measuredYieldGrams: 40,
        elapsedSeconds: 34,
        firstDropSeconds: nil,
        observation: SensoryObservation(tasteVerdict: .underExtracted, flowVerdict: .slow, notes: [.channeling]),
        createdAt: fixedDate(day: 12, hour: 13)
    )

    public static var allShots: [ShotAttempt] {
        [shotSourFast, shotBalanced, shotBitterSlow, shotConflicting]
    }

    public static func seed(_ writer: any DatabaseWriter) throws {
        let beans = SQLiteBeanRepository(writer: writer)
        let grinders = SQLiteGrinderRepository(writer: writer)
        let baskets = SQLiteBasketRepository(writer: writer)
        let recipes = SQLiteRecipeRepository(writer: writer)
        let shots = SQLiteShotRepository(writer: writer)

        try beans.save(beanEthiopia)
        try beans.save(beanColombia)
        try grinders.save(grinderNiche)
        try baskets.save(basketVST18)
        try recipes.save(recipeEthiopia)
        try recipes.save(recipeColombia)
        for shot in allShots {
            try shots.save(shot)
        }
    }

    static func fixedDate(day: Int, hour: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = day
        components.hour = hour
        components.minute = 0
        components.second = 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: components)!
    }
}
