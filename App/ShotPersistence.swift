import DialShotKit
import DialShotStore
import Foundation

@MainActor
final class ShotPersistence {
    private(set) var recipe: RecipeSnapshot
    private(set) var workspaceBeanID: BeanBag.ID?
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
        let database = try DialShotDatabaseFactory.makeQueue(path: databaseURL.path)
        let beans = SQLiteBeanRepository(writer: database)
        let grinders = SQLiteGrinderRepository(writer: database)
        let baskets = SQLiteBasketRepository(writer: database)
        let recipes = SQLiteRecipeRepository(writer: database)
        self.beans = beans
        self.grinders = grinders
        self.recipes = recipes
        shots = SQLiteShotRepository(writer: database)

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
        let names = Dictionary(uniqueKeysWithValues: try beans.list().map { ($0.id, $0.name) })
        let grinderNames = Dictionary(uniqueKeysWithValues: try grinders.list().map { ($0.id, $0.name) })
        return try shots.list(beanID: nil, limit: nil).map { record in
            HistoryShot(
                attempt: record.attempt,
                beanName: names[record.attempt.recipe.beanID] ?? "Unknown bean",
                grinderName: grinderNames[record.attempt.recipe.grinderID] ?? "Unknown grinder",
                grinderSetting: record.grinderSettingLabel
            )
        }
    }

    func save(_ review: ShotReview) throws {
        try shots.save(review.attempt, suggestion: review.suggestion)
    }
}
