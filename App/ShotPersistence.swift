import DialShotKit
import DialShotStore
import Foundation

@MainActor
final class ShotPersistence {
    let recipe: RecipeSnapshot
    private let shots: SQLiteShotRepository

    init() throws {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let database = try DialShotDatabaseFactory.makeQueue(path: support.appendingPathComponent("DialShot.sqlite").path)
        let beans = SQLiteBeanRepository(writer: database)
        let grinders = SQLiteGrinderRepository(writer: database)
        let baskets = SQLiteBasketRepository(writer: database)
        let recipes = SQLiteRecipeRepository(writer: database)
        shots = SQLiteShotRepository(writer: database)

        if let latest = try recipes.list(beanID: nil).first {
            recipe = latest.snapshot
        } else {
            let bean = BeanBag(name: "First bean")
            let grinder = GrinderProfile(name: "Grinder", settingLabel: "Set your grinder")
            let basket = BasketProfile(name: "18 g basket", nominalDoseGrams: 18)
            try beans.save(bean)
            try grinders.save(grinder)
            try baskets.save(basket)
            let snapshot = try RecipeSnapshot(
                beanID: bean.id,
                grinderID: grinder.id,
                basketID: basket.id,
                doseGrams: 18,
                targetYieldGrams: 36,
                targetTimeSeconds: 30
            )
            try recipes.save(RecipeRecord(name: "Starter recipe", snapshot: snapshot))
            recipe = snapshot
        }
    }

    func save(_ review: ShotReview) throws {
        try shots.save(review.attempt, suggestion: review.suggestion)
    }
}
