import GRDB

/// Ordered, forward-only database migrations for Dial Shot's local SQLite store.
public enum DialShotDatabaseMigrator {
    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1-initial-schema") { db in
            try db.execute(sql: """
                CREATE TABLE bean_bag (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    roastDate REAL,
                    createdAt REAL NOT NULL
                );

                CREATE TABLE grinder_profile (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    settingLabel TEXT NOT NULL,
                    createdAt REAL NOT NULL
                );

                CREATE TABLE basket_profile (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    nominalDoseGrams TEXT NOT NULL,
                    createdAt REAL NOT NULL
                );

                CREATE TABLE recipe (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT,
                    beanId TEXT NOT NULL REFERENCES bean_bag(id) ON DELETE CASCADE,
                    grinderId TEXT NOT NULL REFERENCES grinder_profile(id) ON DELETE RESTRICT,
                    basketId TEXT NOT NULL REFERENCES basket_profile(id) ON DELETE RESTRICT,
                    doseGrams TEXT NOT NULL,
                    targetYieldGrams TEXT NOT NULL,
                    targetTimeSeconds INTEGER NOT NULL CHECK (targetTimeSeconds >= 0),
                    createdAt REAL NOT NULL
                );

                CREATE TABLE shot_attempt (
                    id TEXT PRIMARY KEY NOT NULL,
                    beanId TEXT NOT NULL REFERENCES bean_bag(id) ON DELETE CASCADE,
                    grinderId TEXT NOT NULL REFERENCES grinder_profile(id) ON DELETE RESTRICT,
                    basketId TEXT NOT NULL REFERENCES basket_profile(id) ON DELETE RESTRICT,
                    recipeId TEXT REFERENCES recipe(id) ON DELETE SET NULL,
                    doseGrams TEXT NOT NULL,
                    targetYieldGrams TEXT NOT NULL,
                    targetTimeSeconds INTEGER NOT NULL CHECK (targetTimeSeconds >= 0),
                    measuredYieldGrams TEXT NOT NULL,
                    brewRatioValue TEXT NOT NULL,
                    elapsedSeconds INTEGER NOT NULL CHECK (elapsedSeconds >= 0),
                    firstDropSeconds INTEGER CHECK (
                        firstDropSeconds IS NULL OR
                        (firstDropSeconds >= 0 AND firstDropSeconds <= elapsedSeconds)
                    ),
                    tasteVerdict TEXT,
                    flowVerdict TEXT,
                    sensoryNotesJson TEXT NOT NULL,
                    suggestionType TEXT NOT NULL CHECK (
                        suggestionType IN ('adjustment', 'noChange', 'insufficientEvidence')
                    ),
                    suggestedAdjustmentAction TEXT,
                    suggestedAdjustmentRule TEXT,
                    suggestedAdjustmentRationale TEXT,
                    createdAt REAL NOT NULL
                );
            """)
        }

        migrator.registerMigration("v2-query-indexes") { db in
            try db.execute(sql: """
                CREATE INDEX idx_recipe_bean_created
                    ON recipe(beanId, createdAt DESC);
                CREATE INDEX idx_shot_attempt_bean_created
                    ON shot_attempt(beanId, createdAt DESC);
                CREATE INDEX idx_shot_attempt_created
                    ON shot_attempt(createdAt DESC);
            """)
        }

        return migrator
    }

    public static let identifiers = ["v1-initial-schema", "v2-query-indexes"]
}

/// Creates a GRDB queue configured for strict local relational integrity.
public enum DialShotDatabaseFactory {
    public static func makeQueue(path: String = ":memory:") throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let queue = try DatabaseQueue(path: path, configuration: configuration)
        try DialShotDatabaseMigrator.migrator.migrate(queue)
        return queue
    }
}
