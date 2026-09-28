import Foundation
import Testing
@testable import DialShotKit

@Suite("Shot timer and capture")
struct ShotCaptureTests {
    private func recipe() throws -> RecipeSnapshot {
        try RecipeSnapshot(
            beanID: BeanBag(name: "Bean").id,
            grinderID: GrinderProfile(name: "Grinder", settingLabel: "10").id,
            basketID: BasketProfile(name: "Basket", nominalDoseGrams: 18).id,
            doseGrams: 18,
            targetYieldGrams: 36,
            targetTimeSeconds: 30
        )
    }

    @Test("elapsed uses injected uptime across an app background gap")
    func backgroundGap() {
        var timer = ShotTimer()
        timer.start(at: 100)
        #expect(timer.elapsedSeconds(at: 102.9) == 2)
        // No process tick or sleep is needed while the app is backgrounded.
        #expect(timer.elapsedSeconds(at: 127.8) == 27)
        let firstDropRecorded = timer.markFirstDrop(at: 128.1)
        #expect(firstDropRecorded)
        #expect(timer.firstDropSeconds == 28)
        timer.stop(at: 132.7)
        #expect(timer.elapsedSeconds(at: 200) == 32)
    }

    @Test("uptime regressions cannot reduce elapsed or move first drop backwards")
    func regressionClamped() {
        var timer = ShotTimer()
        timer.start(at: 50)
        #expect(timer.elapsedSeconds(at: 58.9) == 8)
        #expect(timer.elapsedSeconds(at: 53) == 8)
        let firstDropRecorded = timer.markFirstDrop(at: 51)
        #expect(firstDropRecorded)
        #expect(timer.firstDropSeconds == 8)
        let duplicateRecorded = timer.markFirstDrop(at: 60)
        #expect(!duplicateRecorded)
        timer.stop(at: 52)
        #expect(timer.elapsedSeconds(at: 52) == 8)
    }

    @Test("capture requires stopped timer and actual yield before review")
    func reviewReadiness() throws {
        var capture = ShotCapture(recipe: try recipe())
        #expect(throws: ShotCaptureError.self) { try capture.review() }
        capture.start(at: 10)
        capture.measuredYieldGrams = 34
        #expect(throws: ShotCaptureError.self) { try capture.review() }
        capture.stop(at: 40)
        let review = try capture.review()
        #expect(review.attempt.elapsedSeconds == 30)
        #expect(review.attempt.measuredYieldGrams == 34)
        #expect(review.attempt.brewRatio == (try BrewRatio(doseGrams: 18, yieldGrams: 34)))
        #expect(review.suggestion.isInsufficientEvidence)
    }

    @Test("review retains captured markers and exact engine recommendation")
    func reviewSuggestion() throws {
        var capture = ShotCapture(recipe: try recipe())
        capture.start(at: 100)
        let firstDropRecorded = capture.markFirstDrop(at: 107)
        #expect(firstDropRecorded)
        capture.stop(at: 123)
        capture.measuredYieldGrams = 32
        capture.notes = [.sour, .channeling]
        capture.flowVerdict = .fast
        let review = try capture.review()
        #expect(review.attempt.firstDropSeconds == 7)
        #expect(review.attempt.observation.notes.contains(.channeling))
        #expect(review.suggestion == DialInEngine.suggest(for: review.attempt))
        guard case .adjustment(let adjustment) = review.suggestion else {
            Issue.record("Expected engine adjustment")
            return
        }
        #expect(adjustment.rule == .underExtractedFastFlow)
    }
}
