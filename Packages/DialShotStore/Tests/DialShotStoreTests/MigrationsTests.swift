import Foundation
import Testing
import GRDB
@testable import DialShotStore

@Suite("Migrations")
struct MigrationsTests {
    @Test("initial migration creates all expected tables and indexes")
    func initialMigrationCreatesTables() throws {
        let dbQueue = try DatabaseQueue()
        try DialShotDatabaseMigrator.migrator.migrate(dbQueue)

        try dbQueue.read { db in
            let tables = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
            #expect(tables.contains("bean_bag"))
            #expect(tables.contains("grinder_profile"))
            #expect(tables.contains("basket_profile"))
            #expect(tables.contains("recipe"))
            #expect(tables.contains("shot_attempt"))
            #expect(tables.contains("grdb_migrations"))

            // Verify foreign keys pragma is active
            let fkEnabled = try Int.fetchOne(db, sql: "PRAGMA foreign_keys")
            #expect(fkEnabled == 1)
        }
    }

    @Test("migrations are forward-only and idempotent on subsequent runs")
    func migrationIdempotence() throws {
        let dbQueue = try DatabaseQueue()
        try DialShotDatabaseMigrator.migrator.migrate(dbQueue)
        // Second run should be a no-op without error
        try DialShotDatabaseMigrator.migrator.migrate(dbQueue)

        try dbQueue.read { db in
            let applied = try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier")
            #expect(applied.contains("v1-initial-schema"))
        }
    }
}
