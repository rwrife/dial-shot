import Foundation
import Testing
import GRDB
import DialShotKit
@testable import DialShotStore

@Suite("Relational integrity and cascade behaviors")
struct RelationalIntegrityAndCascadeTests {
    private func makeQueue() throws -> DatabaseQueue {
        try DialShotDatabaseFactory.makeQueue()
    }

    @Test("foreign keys pragma is enforced on write queue")
    func foreignKeysEnforced() throws {
        let queue = try makeQueue()
        let grinders = SQLiteGrinderRepository(writer: queue)
        let baskets = SQLiteBasketRepository(writer: queue)
        let recipes = SQLiteRecipeRepository(writer: queue)

        let grinder = RepositoryFixtures.makeGrinder()
        let basket = RepositoryFixtures.makeBasket()
        try grinders.save(grinder)
        try baskets.save(basket)

        // Attempt to insert recipe with non-existent bean
        let orphanBeanID = BeanBag.ID()
        let snapshot = try RecipeSnapshot(
            beanID: orphanBeanID,
            grinderID: grinder.id,
            basketID: basket.id,
            doseGrams: 18,
            targetYieldGrams: 36,
            targetTimeSeconds: 30
        )
        let record = RecipeRecord(name: "Orphan", snapshot: snapshot)

        #expect(throws: DatabaseError.self) {
            try recipes.save(record)
        }
    }

    @Test("deleting a bean bag cascades and removes its recipes and shots")
    func deleteBeanCascadesToRecipesAndShots() throws {
        let queue = try makeQueue()
        let beans = SQLiteBeanRepository(writer: queue)
        let grinders = SQLiteGrinderRepository(writer: queue)
        let baskets = SQLiteBasketRepository(writer: queue)
        let recipes = SQLiteRecipeRepository(writer: queue)
        let shots = SQLiteShotRepository(writer: queue)

        let bean = RepositoryFixtures.makeBean()
        let grinder = RepositoryFixtures.makeGrinder()
        let basket = RepositoryFixtures.makeBasket()
        try beans.save(bean)
        try grinders.save(grinder)
        try baskets.save(basket)

        let snapshot = try RepositoryFixtures.makeRecipeSnapshot(bean: bean, grinder: grinder, basket: basket)
        let recipeRecord = RecipeRecord(name: "Active recipe", snapshot: snapshot)
        try recipes.save(recipeRecord)

        let shot = try RepositoryFixtures.makeShot(recipe: snapshot)
        try shots.save(shot)

        #expect(try recipes.get(id: recipeRecord.id) != nil)
        #expect(try shots.get(id: shot.id) != nil)
        #expect(try shots.count(beanID: bean.id) == 1)

        // Cascade delete bean
        try beans.delete(id: bean.id)

        #expect(try beans.get(id: bean.id) == nil)
        #expect(try recipes.get(id: recipeRecord.id) == nil)
        #expect(try shots.get(id: shot.id) == nil)
        #expect(try shots.count(beanID: bean.id) == 0)
    }

    @Test("deleting an active grinder or basket is restricted when referenced")
    func deleteReferencedGrinderOrBasketIsRestricted() throws {
        let queue = try makeQueue()
        let beans = SQLiteBeanRepository(writer: queue)
        let grinders = SQLiteGrinderRepository(writer: queue)
        let baskets = SQLiteBasketRepository(writer: queue)
        let recipes = SQLiteRecipeRepository(writer: queue)

        let bean = RepositoryFixtures.makeBean()
        let grinder = RepositoryFixtures.makeGrinder()
        let basket = RepositoryFixtures.makeBasket()
        try beans.save(bean)
        try grinders.save(grinder)
        try baskets.save(basket)

        let snapshot = try RepositoryFixtures.makeRecipeSnapshot(bean: bean, grinder: grinder, basket: basket)
        try recipes.save(RecipeRecord(name: "Test", snapshot: snapshot))

        // Deleting grinder referenced by recipe violates ON DELETE RESTRICT
        #expect(throws: DatabaseError.self) {
            try grinders.delete(id: grinder.id)
        }

        // Deleting basket referenced by recipe violates ON DELETE RESTRICT
        #expect(throws: DatabaseError.self) {
            try baskets.delete(id: basket.id)
        }
    }
}
