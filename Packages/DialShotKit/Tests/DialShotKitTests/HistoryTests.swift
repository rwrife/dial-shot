import Foundation
import XCTest
@testable import DialShotKit

final class HistoryTests: XCTestCase {
    private let bean = BeanBag(name: "House")
    private let grinder = GrinderProfile(name: "Hand", settingLabel: "7")
    private let basket = BasketProfile(name: "18", nominalDoseGrams: 18)

    private func item(_ seconds: Int, _ verdict: TasteVerdict?, _ notes: [SensoryNote], date: TimeInterval, setting: String? = "7", grinderID: GrinderProfile.ID? = nil, dose: Decimal = 18, yield: Decimal = 35) throws -> HistoryShot {
        let recipe = try RecipeSnapshot(beanID: bean.id, grinderID: grinderID ?? grinder.id, basketID: basket.id, doseGrams: dose, targetYieldGrams: 36, targetTimeSeconds: 30)
        let attempt = try ShotAttempt(recipe: recipe, measuredYieldGrams: yield, elapsedSeconds: seconds, firstDropSeconds: nil, observation: SensoryObservation(tasteVerdict: verdict, flowVerdict: nil, notes: notes), createdAt: Date(timeIntervalSince1970: date))
        return HistoryShot(attempt: attempt, beanName: bean.name, grinderName: grinder.name, grinderSetting: setting)
    }

    func testHistoryFiltersAllFieldsAndOrdersChronologically() throws {
        let older = try item(25, .underExtracted, [.sour], date: 10)
        let newer = try item(30, .balanced, [.balanced], date: 20)
        XCTAssertEqual(ShotHistory.filter([newer, older], using: .init(beanQuery: "hou", grinderQuery: "HAN", from: Date(timeIntervalSince1970: 0), through: Date(timeIntervalSince1970: 10), tasteVerdict: .underExtracted)).map(\.id), [older.id])
        XCTAssertEqual(ShotHistory.filter([newer, older], using: .init()).map(\.id), [older.id, newer.id])
        XCTAssertEqual(ShotHistory.filter([newer, older], using: .init(beanQuery: "missing")).count, 0)
        XCTAssertEqual(ShotHistory.filter([newer, older], using: .init(grinderQuery: "missing")).count, 0)
        XCTAssertEqual(ShotHistory.filter([newer, older], using: .init(from: Date(timeIntervalSince1970: 11))).map(\.id), [newer.id])
        XCTAssertEqual(ShotHistory.filter([newer, older], using: .init(through: Date(timeIntervalSince1970: 19))).map(\.id), [older.id])
        XCTAssertEqual(ShotHistory.filter([newer, older], using: .init(tasteVerdict: .balanced)).map(\.id), [newer.id])
    }

    func testComparisonRequiresTwoDistinctShotsAndScopesGrinderSettings() throws {
        let first = try item(25, .underExtracted, [.sour], date: 10)
        let second = try item(30, .balanced, [.balanced], date: 20, setting: "8")
        XCTAssertThrowsError(try ShotComparison([first]))
        XCTAssertThrowsError(try ShotComparison([first, first]))
        let comparison = try ShotComparison([first, second])
        XCTAssertFalse(comparison.doseDifferent)
        XCTAssertTrue(comparison.timeDifferent)
        XCTAssertFalse(comparison.yieldDifferent)
        let changed = try item(30, .balanced, [.balanced], date: 21, setting: "8", dose: 19, yield: 38)
        let changedComparison = try ShotComparison([first, changed])
        XCTAssertTrue(changedComparison.doseDifferent)
        XCTAssertTrue(changedComparison.yieldDifferent)
        XCTAssertEqual(comparison.grinderSettingDifferent, true)
        XCTAssertTrue(comparison.sensoryDifferent)
        XCTAssertTrue(comparison.tasteDifferent)
        XCTAssertTrue(comparison.notesDifferent)
        XCTAssertFalse(comparison.flowDifferent)
        let otherGrinder = try item(30, .balanced, [.balanced], date: 20, setting: "8", grinderID: GrinderProfile.ID())
        let cross = try ShotComparison([first, otherGrinder])
        XCTAssertNil(cross.grinderSettingDifferent)
        let missingSetting = try item(30, .balanced, [.balanced], date: 22, setting: nil)
        XCTAssertNil(try ShotComparison([first, missingSetting]).grinderSettingDifferent)
        let otherBean = BeanBag(name: "Other")
        let otherRecipe = try RecipeSnapshot(beanID: otherBean.id, grinderID: grinder.id, basketID: basket.id, doseGrams: 18, targetYieldGrams: 36, targetTimeSeconds: 30)
        let otherAttempt = try ShotAttempt(recipe: otherRecipe, measuredYieldGrams: 35, elapsedSeconds: 30, firstDropSeconds: nil, observation: .balanced)
        XCTAssertThrowsError(try ShotComparison([first, HistoryShot(attempt: otherAttempt, beanName: otherBean.name, grinderName: grinder.name, grinderSetting: "7")]))
    }

    func testTrendKeepsUnknownAndConflictingSensoryEvidenceUnknown() throws {
        let first = try item(24, .underExtracted, [.sour], date: 10)
        let unknown = try item(26, nil, [], date: 20)
        let conflict = try item(28, .balanced, [.sour], date: 30)
        let last = try item(30, .balanced, [.balanced], date: 40)
        let trend = ShotTrend([last, conflict, first, unknown])
        XCTAssertEqual(trend.points.map(\.elapsedSeconds), [24, 26, 28, 30])
        XCTAssertEqual(trend.points.map(\.sensoryBalance), [.underExtracted, .unknown, .unknown, .balanced])
        XCTAssertEqual(trend.timeChangeSeconds, 6)
    }
}
