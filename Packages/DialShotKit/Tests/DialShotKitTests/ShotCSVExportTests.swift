import Foundation
import XCTest
@testable import DialShotKit

/// Issue #7: flat CSV export of the shot log with the exact header contract
/// `date,bean,roast,grinder,setting,dose,yield,ratio,time,taste,adjustment`.
/// The builder is pure and deterministic so it is verifiable without any
/// UI, file picker, or share sheet.
final class ShotCSVExportTests: XCTestCase {
    private func fixedDate(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        guard let date = formatter.date(from: iso) else { fatalError("bad fixture date \(iso)") }
        return date
    }

    private func fixtureShot(
        id: UUID,
        bean: BeanBag,
        grinder: GrinderProfile,
        dose: Decimal,
        yield: Decimal,
        measured: Decimal,
        seconds: Int,
        taste: TasteVerdict?,
        suggestion: DialInSuggestion?,
        createdAt: Date,
        grinderSetting: String? = "7"
    ) throws -> HistoryShot {
        let snapshot = try RecipeSnapshot(
            beanID: bean.id, grinderID: grinder.id,
            basketID: BasketProfile.ID(),
            doseGrams: dose, targetYieldGrams: yield, targetTimeSeconds: 30
        )
        let attempt = try ShotAttempt(
            id: id, recipe: snapshot, measuredYieldGrams: measured,
            elapsedSeconds: seconds, firstDropSeconds: nil,
            observation: SensoryObservation(tasteVerdict: taste, flowVerdict: nil, notes: []),
            createdAt: createdAt
        )
        return HistoryShot(
            attempt: attempt,
            beanName: bean.name,
            beanRoastDate: bean.roastDate,
            grinderName: grinder.name,
            grinderSetting: grinderSetting,
            suggestion: suggestion
        )
    }

    private func makeFixtures() throws -> (bean: BeanBag, grinder: GrinderProfile) {
        let roast = fixedDate("2026-09-01 08:00:00 +0000")
        let bean = BeanBag(id: .init(rawValue: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!), name: "Ethiopia, Guji", roastDate: roast)
        let grinder = GrinderProfile(id: .init(rawValue: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!), name: "1Z J-Mill", settingLabel: "7")
        return (bean, grinder)
    }

    func testHeaderIsTheContract() {
        XCTAssertEqual(ShotCSVExport.header, "date,bean,roast,grinder,setting,dose,yield,ratio,time,taste,adjustment")
        XCTAssertEqual(ShotCSVExport.csv([]), ShotCSVExport.header + "\r\n")
    }

    func testRowOrderIsChronologicalThenIDLikeHistoryFilter() throws {
        let (bean, grinder) = try makeFixtures()
        let laterID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let earlierID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let later = try fixtureShot(
            id: laterID, bean: bean, grinder: grinder, dose: 18, yield: 36, measured: 34,
            seconds: 30, taste: .balanced, suggestion: .noChangeRecommended,
            createdAt: fixedDate("2026-09-10 09:00:00 +0000")
        )
        let earlier = try fixtureShot(
            id: earlierID, bean: bean, grinder: grinder, dose: 18, yield: 36, measured: 36,
            seconds: 28, taste: .underExtracted, suggestion: nil,
            createdAt: fixedDate("2026-09-09 09:00:00 +0000")
        )
        let csv = ShotCSVExport.csv([later, earlier])
        let lines = csv.split(separator: "\r\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[1].hasPrefix("2026-09-09"), "earlier shot must come first, got: \(lines[1])")
        XCTAssertTrue(lines[2].hasPrefix("2026-09-10"))
    }

    func testRowRendersEveryColumnExactly() throws {
        let (bean, grinder) = try makeFixtures()
        let shot = try fixtureShot(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            bean: bean, grinder: grinder, dose: 18, yield: 36, measured: 34,
            seconds: 31, taste: .underExtracted,
            suggestion: .adjustment(Adjustment(action: .grindFiner, rule: .underExtractedFastFlow)),
            createdAt: fixedDate("2026-09-09 12:34:56 +0000")
        )
        let row = ShotCSVExport.row(shot)
        XCTAssertEqual(
            row,
            "2026-09-09T12:34:56Z,\"Ethiopia, Guji\",2026-09-01T08:00:00Z,1Z J-Mill,7,18,34,1:1.9,31s,under-extracted,grindFiner"
        )
    }

    func testMissingEvidenceExportsExplicitTokensNeverBlankGuesses() throws {
        let (bean, grinder) = try makeFixtures()
        let shot = try fixtureShot(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            bean: bean, grinder: grinder, dose: 18, yield: 36, measured: 36,
            seconds: 30, taste: nil, suggestion: .insufficientEvidence(reason: "no flow verdict"),
            createdAt: fixedDate("2026-09-09 09:00:00 +0000"),
            grinderSetting: nil
        )
        let row = ShotCSVExport.row(shot)
        XCTAssertTrue(row.contains(",not recorded,"), "missing grinder setting must be explicit: \(row)")
        XCTAssertTrue(row.hasSuffix(",unknown,unknown"), "missing taste and adjustment must be explicit: \(row)")
        // Bean with no roast date also gets an explicit token.
        let noRoast = BeanBag(id: BeanBag.ID(rawValue: UUID()), name: "NoRoast")
        let noRoastShot = try fixtureShot(
            id: UUID(), bean: noRoast, grinder: grinder, dose: 18, yield: 36, measured: 36,
            seconds: 30, taste: .balanced, suggestion: .noChangeRecommended,
            createdAt: fixedDate("2026-09-09 09:00:00 +0000")
        )
        let noRoastRow = ShotCSVExport.row(noRoastShot)
        XCTAssertTrue(noRoastRow.contains("NoRoast,not recorded,1Z"), "missing roast date must be explicit: \(noRoastRow)")
    }

    func testFieldsWithCommasAndQuotesAreRFC4180Escaped() throws {
        let (_, grinder) = try makeFixtures()
        let tricky = BeanBag(id: .init(rawValue: UUID()), name: "Bean \"Special\", lot 3", roastDate: nil)
        let shot = try fixtureShot(
            id: UUID(), bean: tricky, grinder: grinder, dose: 18, yield: 36, measured: 36,
            seconds: 30, taste: .balanced, suggestion: .noChangeRecommended,
            createdAt: fixedDate("2026-09-09 09:00:00 +0000")
        )
        let row = ShotCSVExport.row(shot)
        XCTAssertTrue(row.contains("\"Bean \"\"Special\"\", lot 3\""), "quotes and commas must escape: \(row)")
    }

    func testDecimalsExportWithoutFloatDrift() throws {
        let (bean, grinder) = try makeFixtures()
        let dose = Decimal(string: "17.7")!
        let shot = try fixtureShot(
            id: UUID(), bean: bean, grinder: grinder, dose: dose, yield: 36, measured: Decimal(string: "35.4")!,
            seconds: 30, taste: .balanced, suggestion: .noChangeRecommended,
            createdAt: fixedDate("2026-09-09 09:00:00 +0000")
        )
        let row = ShotCSVExport.row(shot)
        XCTAssertTrue(row.contains(",17.7,35.4,"), "decimals must export canonically: \(row)")
        XCTAssertFalse(row.contains("17.700000000"), "no float drift allowed: \(row)")
    }

    func testDeterministicAcrossRunsAndInputOrder() throws {
        let (bean, grinder) = try makeFixtures()
        let a = try fixtureShot(id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!, bean: bean, grinder: grinder, dose: 18, yield: 36, measured: 34, seconds: 30, taste: .balanced, suggestion: .noChangeRecommended, createdAt: fixedDate("2026-09-10 09:00:00 +0000"))
        let b = try fixtureShot(id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!, bean: bean, grinder: grinder, dose: 18, yield: 36, measured: 36, seconds: 28, taste: .balanced, suggestion: .noChangeRecommended, createdAt: fixedDate("2026-09-09 09:00:00 +0000"))
        XCTAssertEqual(ShotCSVExport.csv([a, b]), ShotCSVExport.csv([b, a]))
        XCTAssertEqual(ShotCSVExport.csv([a, b]), ShotCSVExport.csv([a, b]))
    }
}
