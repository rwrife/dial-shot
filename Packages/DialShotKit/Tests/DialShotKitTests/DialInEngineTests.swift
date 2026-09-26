import Foundation
import Testing
@testable import DialShotKit

@Suite("DialInEngine")
struct DialInEngineTests {
    private func makeRecipe(targetTime: Int = 30) throws -> RecipeSnapshot {
        let bean = BeanBag(name: "Test Bean")
        let grinder = GrinderProfile(name: "Test Grinder", settingLabel: "10")
        let basket = BasketProfile(name: "18g", nominalDoseGrams: Decimal(string: "18")!)
        return try RecipeSnapshot(
            beanID: bean.id,
            grinderID: grinder.id,
            basketID: basket.id,
            doseGrams: Decimal(string: "18")!,
            targetYieldGrams: Decimal(string: "36")!,
            targetTimeSeconds: targetTime
        )
    }

    @Test("sour + fast flow suggests grinding finer, citing the triggering rule")
    func sourFastSuggestsFiner() throws {
        let recipe = try makeRecipe()
        let observation = SensoryObservation(tasteVerdict: .underExtracted, flowVerdict: .fast, notes: [.sour])
        let shot = try ShotAttempt(recipe: recipe, measuredYieldGrams: 36, elapsedSeconds: 22, firstDropSeconds: nil, observation: observation)

        let result = DialInEngine.suggest(for: shot)

        guard case .adjustment(let adjustment) = result else {
            Issue.record("expected an adjustment, got \(result)")
            return
        }
        #expect(adjustment.action == .grindFiner)
        #expect(adjustment.rule == .underExtractedFastFlow)
        #expect(adjustment.rationale.contains("sour") || adjustment.rationale.contains("under-extracted"))
    }

    @Test("bitter + slow flow suggests grinding coarser")
    func bitterSlowSuggestsCoarser() throws {
        let recipe = try makeRecipe()
        let observation = SensoryObservation(tasteVerdict: .overExtracted, flowVerdict: .slow, notes: [.bitter])
        let shot = try ShotAttempt(recipe: recipe, measuredYieldGrams: 36, elapsedSeconds: 40, firstDropSeconds: nil, observation: observation)

        let result = DialInEngine.suggest(for: shot)

        guard case .adjustment(let adjustment) = result else {
            Issue.record("expected an adjustment, got \(result)")
            return
        }
        #expect(adjustment.action == .grindCoarser)
        #expect(adjustment.rule == .overExtractedSlowFlow)
    }

    @Test("balanced taste with on-target flow recommends no change")
    func balancedRecommendsNoChange() throws {
        let recipe = try makeRecipe()
        let shot = try ShotAttempt(recipe: recipe, measuredYieldGrams: 36, elapsedSeconds: 30, firstDropSeconds: nil, observation: .balanced)

        let result = DialInEngine.suggest(for: shot)

        #expect(result == .noChangeRecommended)
    }

    @Test("conflicting evidence (sour taste but slow flow) yields explicit unknown, never a guess")
    func conflictingEvidenceIsUnknown() throws {
        let recipe = try makeRecipe()
        let observation = SensoryObservation(tasteVerdict: .underExtracted, flowVerdict: .slow, notes: [.sour])
        let shot = try ShotAttempt(recipe: recipe, measuredYieldGrams: 36, elapsedSeconds: 40, firstDropSeconds: nil, observation: observation)

        let result = DialInEngine.suggest(for: shot)

        guard case .insufficientEvidence(let reason) = result else {
            Issue.record("expected insufficientEvidence, got \(result)")
            return
        }
        #expect(reason.isEmpty == false)
    }

    @Test("missing flow verdict yields insufficient evidence rather than guessing a direction")
    func missingFlowVerdictIsUnknown() throws {
        let recipe = try makeRecipe()
        let observation = SensoryObservation(tasteVerdict: .underExtracted, flowVerdict: nil, notes: [.sour])
        let shot = try ShotAttempt(recipe: recipe, measuredYieldGrams: 36, elapsedSeconds: 30, firstDropSeconds: nil, observation: observation)

        let result = DialInEngine.suggest(for: shot)

        #expect(result.isInsufficientEvidence)
    }

    @Test("compound-but-consistent evidence still yields exactly one adjustment variant, not a list")
    func atMostOneAdjustment() throws {
        let recipe = try makeRecipe()
        let observation = SensoryObservation(tasteVerdict: .underExtracted, flowVerdict: .fast, notes: [.sour, .thin])
        let shot = try ShotAttempt(recipe: recipe, measuredYieldGrams: 36, elapsedSeconds: 20, firstDropSeconds: nil, observation: observation)

        guard case .adjustment(let adjustment) = DialInEngine.suggest(for: shot) else {
            Issue.record("expected a single adjustment for compound-but-consistent evidence")
            return
        }
        #expect(adjustment.rule == .underExtractedFastFlow)
        #expect(adjustment.action == .grindFiner)
        // The suggestion enum's own shape (one associated Adjustment, not an
        // array) is what forbids more than one adjustment; this canary would
        // fail immediately if suggest(for:) were changed to return [Adjustment].
        let mirror = Mirror(reflecting: adjustment)
        #expect(mirror.children.count == 3, "Adjustment must carry exactly action+rule+rationale, never a collection of adjustments")
    }

    @Test("a contradicting sensory note vetoes the taste/flow rule instead of guessing")
    func contradictingNoteYieldsUnknown() throws {
        let recipe = try makeRecipe()
        // Taste/flow alone would trigger grindFiner, but a bitter note directly
        // contradicts an under-extracted verdict — the engine must not ignore it.
        let observation = SensoryObservation(tasteVerdict: .underExtracted, flowVerdict: .fast, notes: [.bitter])
        let shot = try ShotAttempt(recipe: recipe, measuredYieldGrams: 36, elapsedSeconds: 20, firstDropSeconds: nil, observation: observation)

        let result = DialInEngine.suggest(for: shot)

        #expect(result.isInsufficientEvidence)
    }

    @Test("an over-extracted verdict contradicted by a sour note yields unknown")
    func contradictingSourNoteYieldsUnknown() throws {
        let recipe = try makeRecipe()
        let observation = SensoryObservation(tasteVerdict: .overExtracted, flowVerdict: .slow, notes: [.sour])
        let shot = try ShotAttempt(recipe: recipe, measuredYieldGrams: 36, elapsedSeconds: 40, firstDropSeconds: nil, observation: observation)

        let result = DialInEngine.suggest(for: shot)

        #expect(result.isInsufficientEvidence)
    }

    @Test("balanced verdict contradicted by sour note yields unknown")
    func balancedVerdictContradictedBySourNoteIsUnknown() throws {
        let recipe = try makeRecipe()
        let observation = SensoryObservation(tasteVerdict: .balanced, flowVerdict: .onTarget, notes: [.sour])
        let shot = try ShotAttempt(recipe: recipe, measuredYieldGrams: 36, elapsedSeconds: 30, firstDropSeconds: nil, observation: observation)

        let result = DialInEngine.suggest(for: shot)

        #expect(result.isInsufficientEvidence)
    }

    @Test("under-extracted verdict contradicted by balanced note yields unknown")
    func underExtractedContradictedByBalancedNoteIsUnknown() throws {
        let recipe = try makeRecipe()
        let observation = SensoryObservation(tasteVerdict: .underExtracted, flowVerdict: .fast, notes: [.balanced])
        let shot = try ShotAttempt(recipe: recipe, measuredYieldGrams: 36, elapsedSeconds: 22, firstDropSeconds: nil, observation: observation)

        let result = DialInEngine.suggest(for: shot)

        #expect(result.isInsufficientEvidence)
    }

    @Test("on-target flow with under-extracted taste suggests a longer yield ratio")
    func underExtractedOnTargetSuggestsLongerRatio() throws {
        let recipe = try makeRecipe()
        let observation = SensoryObservation(tasteVerdict: .underExtracted, flowVerdict: .onTarget, notes: [.sour])
        let shot = try ShotAttempt(recipe: recipe, measuredYieldGrams: 36, elapsedSeconds: 30, firstDropSeconds: nil, observation: observation)

        guard case .adjustment(let adjustment) = DialInEngine.suggest(for: shot) else {
            Issue.record("expected a yield-ratio adjustment")
            return
        }
        #expect(adjustment.action == .increaseYieldRatio)
        #expect(adjustment.rule == .underExtractedOnTargetFlow)
    }

    @Test("on-target flow with over-extracted taste suggests a shorter yield ratio")
    func overExtractedOnTargetSuggestsShorterRatio() throws {
        let recipe = try makeRecipe()
        let observation = SensoryObservation(tasteVerdict: .overExtracted, flowVerdict: .onTarget, notes: [.bitter])
        let shot = try ShotAttempt(recipe: recipe, measuredYieldGrams: 36, elapsedSeconds: 30, firstDropSeconds: nil, observation: observation)

        guard case .adjustment(let adjustment) = DialInEngine.suggest(for: shot) else {
            Issue.record("expected a yield-ratio adjustment")
            return
        }
        #expect(adjustment.action == .decreaseYieldRatio)
        #expect(adjustment.rule == .overExtractedOnTargetFlow)
    }

    @Test("golden matrix: all 16 taste/flow combinations have their exact bounded outcome")
    func goldenMatrix() throws {
        enum Expected: Equatable {
            case adjustment(AdjustmentRule)
            case noChange
            case unknown
        }

        let fixtures: [(TasteVerdict?, FlowVerdict?, Expected)] = [
            (nil, nil, .unknown),
            (nil, .fast, .unknown),
            (nil, .onTarget, .unknown),
            (nil, .slow, .unknown),
            (.underExtracted, nil, .unknown),
            (.underExtracted, .fast, .adjustment(.underExtractedFastFlow)),
            (.underExtracted, .onTarget, .adjustment(.underExtractedOnTargetFlow)),
            (.underExtracted, .slow, .unknown),
            (.balanced, nil, .unknown),
            (.balanced, .fast, .unknown),
            (.balanced, .onTarget, .noChange),
            (.balanced, .slow, .unknown),
            (.overExtracted, nil, .unknown),
            (.overExtracted, .fast, .unknown),
            (.overExtracted, .onTarget, .adjustment(.overExtractedOnTargetFlow)),
            (.overExtracted, .slow, .adjustment(.overExtractedSlowFlow)),
        ]
        let recipe = try makeRecipe()

        for (taste, flow, expected) in fixtures {
            let observation = SensoryObservation(tasteVerdict: taste, flowVerdict: flow, notes: [])
            let shot = try ShotAttempt(recipe: recipe, measuredYieldGrams: 36, elapsedSeconds: 30, firstDropSeconds: nil, observation: observation)
            let result = DialInEngine.suggest(for: shot)

            switch (expected, result) {
            case (.adjustment(let expectedRule), .adjustment(let adjustment)):
                #expect(adjustment.rule == expectedRule)
            case (.noChange, .noChangeRecommended), (.unknown, .insufficientEvidence):
                break
            default:
                Issue.record("taste=\(String(describing: taste)) flow=\(String(describing: flow)) expected \(expected), got \(result)")
            }
            #expect(DialInEngine.suggest(for: shot) == result)
        }
    }

    @Test("adjustment result round-trips through JSON for persistence")
    func adjustmentCodableRoundTrip() throws {
        let recipe = try makeRecipe()
        let observation = SensoryObservation(tasteVerdict: .underExtracted, flowVerdict: .fast, notes: [.sour])
        let shot = try ShotAttempt(recipe: recipe, measuredYieldGrams: 36, elapsedSeconds: 20, firstDropSeconds: nil, observation: observation)

        let result = DialInEngine.suggest(for: shot)
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(DialInSuggestion.self, from: data)

        #expect(decoded == result)
    }
}
