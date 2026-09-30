import Foundation
import XCTest
import DialShotKit
@testable import DialShotStore

final class HistoryPersistenceTests: XCTestCase {
    func testActiveRecipeAndShotSettingSurviveProfileUpdate() throws {
        let db = try DialShotDatabaseFactory.makeQueue()
        let beans = SQLiteBeanRepository(writer: db)
        let grinders = SQLiteGrinderRepository(writer: db)
        let baskets = SQLiteBasketRepository(writer: db)
        let recipes = SQLiteRecipeRepository(writer: db)
        let shots = SQLiteShotRepository(writer: db)
        let bean = BeanBag(name: "House")
        let grinder = GrinderProfile(name: "Hand", settingLabel: "7")
        let basket = BasketProfile(name: "18", nominalDoseGrams: 18)
        try beans.save(bean); try grinders.save(grinder); try baskets.save(basket)
        let snapshot = try RecipeSnapshot(beanID: bean.id, grinderID: grinder.id, basketID: basket.id, doseGrams: 18, targetYieldGrams: 36, targetTimeSeconds: 30)
        let recipe = RecipeRecord(snapshot: snapshot)
        try recipes.save(recipe)
        try recipes.setActive(recipeID: recipe.id, for: bean.id)
        XCTAssertEqual(try recipes.active(for: bean.id)?.id, recipe.id)
        let shot = try ShotAttempt(recipe: snapshot, measuredYieldGrams: 35, elapsedSeconds: 29, firstDropSeconds: nil, observation: .balanced)
        try shots.save(shot)
        try grinders.save(GrinderProfile(id: grinder.id, name: "Hand", settingLabel: "8"))
        XCTAssertEqual(try shots.get(id: shot.id)?.grinderSettingLabel, "7")
        XCTAssertNoThrow(try shots.save(shot))
        XCTAssertEqual(try shots.get(id: shot.id)?.grinderSettingLabel, "7")
        XCTAssertEqual(try recipes.active(for: bean.id)?.id, recipe.id)
    }

    func testActiveRecipeRejectsAnotherBeansRecipe() throws {
        let db = try DialShotDatabaseFactory.makeQueue()
        let beans = SQLiteBeanRepository(writer: db)
        let grinders = SQLiteGrinderRepository(writer: db)
        let baskets = SQLiteBasketRepository(writer: db)
        let recipes = SQLiteRecipeRepository(writer: db)
        let first = BeanBag(name: "First")
        let second = BeanBag(name: "Second")
        let grinder = GrinderProfile(name: "Hand", settingLabel: "7")
        let basket = BasketProfile(name: "18", nominalDoseGrams: 18)
        try beans.save(first); try beans.save(second); try grinders.save(grinder); try baskets.save(basket)
        let snapshot = try RecipeSnapshot(beanID: first.id, grinderID: grinder.id, basketID: basket.id, doseGrams: 18, targetYieldGrams: 36, targetTimeSeconds: 30)
        let record = RecipeRecord(snapshot: snapshot)
        try recipes.save(record)
        XCTAssertThrowsError(try recipes.setActive(recipeID: record.id, for: second.id))
        XCTAssertNil(try recipes.active(for: second.id))
    }

    func testSelectedWorkspaceBeanPersistsAcrossStoreInstances() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("dialshot-workspace-\(UUID().uuidString).sqlite").path
        let beans = SQLiteBeanRepository(writer: try DialShotDatabaseFactory.makeQueue(path: path))
        let first = BeanBag(name: "First")
        let second = BeanBag(name: "Second")
        try beans.save(first)
        try beans.save(second)

        let recipes = SQLiteRecipeRepository(writer: try DialShotDatabaseFactory.makeQueue(path: path))
        XCTAssertNil(try recipes.selectedWorkspaceBeanID())
        try recipes.setSelectedWorkspaceBeanID(second.id)

        // A fresh store instance (simulating app relaunch) must see the choice.
        let relaunched = SQLiteRecipeRepository(writer: try DialShotDatabaseFactory.makeQueue(path: path))
        XCTAssertEqual(try relaunched.selectedWorkspaceBeanID(), second.id)
        try FileManager.default.removeItem(atPath: path)
    }
}
