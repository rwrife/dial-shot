import DialShotKit
import DialShotStore
import Foundation

@MainActor
final class ShotPersistence {
    private(set) var recipe: RecipeSnapshot?
    private(set) var workspaceBeanID: BeanBag.ID?
    private let backupSource: BackupSource
    private let beans: SQLiteBeanRepository
    private let grinders: SQLiteGrinderRepository
    private let recipes: SQLiteRecipeRepository
    private let shots: SQLiteShotRepository

    init() throws {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let databaseURL = support.appendingPathComponent("DialShot.sqlite")
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-DialShotResetUITestStore") {
            for suffix in ["", "-wal", "-shm"] {
                let url = URL(fileURLWithPath: databaseURL.path + suffix)
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
            }
        }
        #endif
        let existingStore = FileManager.default.fileExists(atPath: databaseURL.path)
        let database = try DialShotDatabaseFactory.makeQueue(path: databaseURL.path)
        let beans = SQLiteBeanRepository(writer: database)
        let grinders = SQLiteGrinderRepository(writer: database)
        let baskets = SQLiteBasketRepository(writer: database)
        let recipes = SQLiteRecipeRepository(writer: database)
        self.beans = beans
        self.grinders = grinders
        self.recipes = recipes
        shots = SQLiteShotRepository(writer: database)
        backupSource = BackupSource(
            beans: beans,
            grinders: grinders,
            baskets: baskets,
            recipes: recipes,
            shots: shots,
            database: database
        )

        if let latest = try recipes.list(beanID: nil).first {
            let remembered = try recipes.selectedWorkspaceBeanID()
            let knownBeans = try beans.list().map(\.id)
            let rememberedBean = remembered.flatMap { knownBeans.contains($0) ? $0 : nil }
            let beanID = rememberedBean ?? latest.snapshot.beanID
            if let active = try recipes.active(for: beanID) {
                recipe = active.snapshot
                workspaceBeanID = beanID
            } else {
                let chosen = (try recipes.list(beanID: beanID).first) ?? latest
                try recipes.setActive(recipeID: chosen.id, for: chosen.snapshot.beanID)
                try recipes.setSelectedWorkspaceBeanID(chosen.snapshot.beanID)
                recipe = chosen.snapshot
                workspaceBeanID = chosen.snapshot.beanID
            }
        } else if existingStore {
            // An explicitly restored empty store remains empty after relaunch.
            recipe = nil
            workspaceBeanID = nil
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
            let starter = RecipeRecord(name: "Starter recipe", snapshot: snapshot)
            try recipes.save(starter)
            try recipes.setActive(recipeID: starter.id, for: bean.id)
            try recipes.setSelectedWorkspaceBeanID(bean.id)
            recipe = snapshot
            workspaceBeanID = bean.id
        }
    }

    func beanList() throws -> [BeanBag] { try beans.list() }

    func recipeList(for beanID: BeanBag.ID) throws -> [RecipeRecord] {
        try recipes.list(beanID: beanID)
    }

    func setActive(_ record: RecipeRecord) throws {
        try recipes.setActive(recipeID: record.id, for: record.snapshot.beanID)
        try recipes.setSelectedWorkspaceBeanID(record.snapshot.beanID)
        recipe = record.snapshot
        workspaceBeanID = record.snapshot.beanID
    }

    /// Selects a bean for capture only when it has a usable recipe. The history
    /// screen may still inspect beans without recipes without changing capture.
    func selectBean(_ beanID: BeanBag.ID?) throws {
        guard let beanID else { return }
        if let active = try recipes.active(for: beanID) {
            try recipes.setSelectedWorkspaceBeanID(beanID)
            recipe = active.snapshot
            workspaceBeanID = beanID
        } else if let latest = try recipes.list(beanID: beanID).first {
            try recipes.setActive(recipeID: latest.id, for: beanID)
            try recipes.setSelectedWorkspaceBeanID(beanID)
            recipe = latest.snapshot
            workspaceBeanID = beanID
        }
    }

    func activeRecipe(for beanID: BeanBag.ID) throws -> RecipeRecord? {
        try recipes.active(for: beanID)
    }

    func history() throws -> [HistoryShot] {
        let beans = try beans.list()
        let names = Dictionary(uniqueKeysWithValues: beans.map { ($0.id, $0.name) })
        let roastDates = Dictionary(uniqueKeysWithValues: beans.map { ($0.id, $0.roastDate) })
        let grinderNames = Dictionary(uniqueKeysWithValues: try grinders.list().map { ($0.id, $0.name) })
        return try shots.list(beanID: nil, limit: nil).map { record in
            HistoryShot(
                attempt: record.attempt,
                beanName: names[record.attempt.recipe.beanID] ?? "Unknown bean",
                beanRoastDate: roastDates[record.attempt.recipe.beanID] ?? nil,
                grinderName: grinderNames[record.attempt.recipe.grinderID] ?? "Unknown grinder",
                grinderSetting: record.grinderSettingLabel,
                suggestion: record.suggestion
            )
        }
    }

    func save(_ review: ShotReview) throws {
        try shots.save(review.attempt, suggestion: review.suggestion)
    }

    // MARK: - Issue #7: user-owned backup and export

    /// Snapshots the complete database into a versioned backup document.
    func backupDocument() throws -> BackupDocument {
        try LocalBackup.document(from: backupSource)
    }

    /// Replaces all local data with the contents of a validated backup
    /// document (one transaction; a failure leaves current data untouched),
    /// then reloads the in-memory recipe/selection so the workspace
    /// immediately reflects the restored store.
    func restoreBackup(_ document: BackupDocument) throws {
        try LocalBackup.restoreAndVerify(document, from: backupSource)
        // Nothing after a committed replacement may throw or mutate SQLite:
        // otherwise the UI could report failure even though old data is gone.
        // This document already passed the exact SQLite rehearsal, so derive
        // the visible capture recipe directly from the validated snapshot.
        let latest = document.beanGroups.flatMap(\.recipes).sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }.first
        let selected = document.beanGroups.first { $0.bean.id == document.selectedBeanID && !$0.recipes.isEmpty }
        let active = selected.flatMap { group in group.recipes.first { $0.id == group.activeRecipeID } }
        let chosen = active ?? selected?.recipes.sorted { $0.createdAt > $1.createdAt }.first ?? latest
        recipe = chosen?.snapshot
        workspaceBeanID = chosen?.snapshot.beanID
    }
}
