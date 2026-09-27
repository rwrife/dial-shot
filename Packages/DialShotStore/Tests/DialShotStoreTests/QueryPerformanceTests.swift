import Foundation
import Testing
import GRDB
import DialShotKit
@testable import DialShotStore

@Suite("Query performance and index coverage")
struct QueryPerformanceTests {
    @Test("query planner uses indexes for filtered and ordered lookups")
    func queryPlannerUsesIndexes() throws {
        let queue = try DialShotDatabaseFactory.makeQueue()

        try queue.read { db in
            func planDetail(_ sql: String, _ args: [DatabaseValueConvertible] = []) throws -> String {
                try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
                    .map { row in String(describing: row["detail"]) }
                    .joined(separator: " ")
            }

            // Query 1: per-bean shots ordered by newest first
            let plan1 = try planDetail("EXPLAIN QUERY PLAN SELECT * FROM shot_attempt WHERE beanId = ? ORDER BY createdAt DESC", ["fake-id"])
            #expect(plan1.contains("idx_shot_attempt_bean_created"), "Expected query to use idx_shot_attempt_bean_created, got: \(plan1)")

            // Query 2: all shots ordered by newest first
            let plan2 = try planDetail("EXPLAIN QUERY PLAN SELECT * FROM shot_attempt ORDER BY createdAt DESC")
            #expect(plan2.contains("idx_shot_attempt_created"), "Expected query to use idx_shot_attempt_created, got: \(plan2)")

            // Query 3: per-bean recipes ordered by newest first
            let plan3 = try planDetail("EXPLAIN QUERY PLAN SELECT * FROM recipe WHERE beanId = ? ORDER BY createdAt DESC", ["fake-id"])
            #expect(plan3.contains("idx_recipe_bean_created"), "Expected query to use idx_recipe_bean_created, got: \(plan3)")
        }
    }

    @Test("query performance on bulk shot history executes well under 50ms")
    func bulkShotQueryPerformance() throws {
        let queue = try DialShotDatabaseFactory.makeQueue()
        let beans = SQLiteBeanRepository(writer: queue)
        let grinders = SQLiteGrinderRepository(writer: queue)
        let baskets = SQLiteBasketRepository(writer: queue)
        let shots = SQLiteShotRepository(writer: queue)

        let bean = RepositoryFixtures.makeBean()
        let grinder = RepositoryFixtures.makeGrinder()
        let basket = RepositoryFixtures.makeBasket()
        try beans.save(bean)
        try grinders.save(grinder)
        try baskets.save(basket)
        let snapshot = try RepositoryFixtures.makeRecipeSnapshot(bean: bean, grinder: grinder, basket: basket)

        // Seed 200 shots
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        for i in 0..<200 {
            let attempt = try ShotAttempt(
                recipe: snapshot,
                measuredYieldGrams: 36,
                elapsedSeconds: 28 + (i % 5),
                firstDropSeconds: 6,
                observation: .balanced,
                createdAt: baseDate.addingTimeInterval(Double(i) * 3600)
            )
            try shots.save(attempt)
        }

        let start = Date()
        let recent = try shots.list(beanID: bean.id, limit: 20)
        let elapsed = Date().timeIntervalSince(start)

        #expect(recent.count == 20)
        #expect(elapsed < 0.05, "Expected list query to complete in < 50ms, took \(elapsed * 1000)ms")
    }
}
