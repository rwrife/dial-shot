import Foundation
import Testing
@testable import DialShotKit

@Suite("Domain models")
struct DomainModelsTests {
    @Test("bean and grinder IDs are stable UUID-backed value types")
    func idsStable() {
        let beanID = BeanBag.ID()
        let grinderID = GrinderProfile.ID()

        #expect(beanID != BeanBag.ID())
        #expect(grinderID != GrinderProfile.ID())
    }

    @Test("recipe snapshot captures immutable brew target values")
    func recipeSnapshot() throws {
        let bean = BeanBag(name: "Ethiopia Guji", roastDate: Date(timeIntervalSince1970: 1_700_000_000))
        let grinder = GrinderProfile(name: "Niche Zero", settingLabel: "12")
        let basket = BasketProfile(name: "18g VST", nominalDoseGrams: Decimal(string: "18")!)
        let recipe = try RecipeSnapshot(
            beanID: bean.id,
            grinderID: grinder.id,
            basketID: basket.id,
            doseGrams: Decimal(string: "18")!,
            targetYieldGrams: Decimal(string: "36")!,
            targetTimeSeconds: 30
        )

        #expect(recipe.targetRatio.displayString == "1:2.0")
        #expect(recipe.targetTimeSeconds == 30)
    }

    @Test("shot attempt is immutable record with derived ratio")
    func shotAttemptDerivedRatio() throws {
        let bean = BeanBag(name: "Kenya AA")
        let grinder = GrinderProfile(name: "Ode Gen 2", settingLabel: "2.1")
        let basket = BasketProfile(name: "18g IMS", nominalDoseGrams: Decimal(string: "18")!)
        let recipe = try RecipeSnapshot(
            beanID: bean.id,
            grinderID: grinder.id,
            basketID: basket.id,
            doseGrams: Decimal(string: "18")!,
            targetYieldGrams: Decimal(string: "36")!,
            targetTimeSeconds: 31
        )

        let observation = SensoryObservation(
            tasteVerdict: .underExtracted,
            flowVerdict: .fast,
            notes: [.sour, .thin]
        )

        let shot = try ShotAttempt(
            recipe: recipe,
            measuredYieldGrams: Decimal(string: "41")!,
            elapsedSeconds: 25,
            firstDropSeconds: 7,
            observation: observation
        )

        #expect(shot.brewRatio.displayString == "1:2.3")
        #expect(shot.elapsedSeconds == 25)
        #expect(shot.observation.notes.contains(.sour))
    }

    @Test("recipe snapshot round-trips through JSON")
    func recipeSnapshotCodableRoundTrip() throws {
        let bean = BeanBag(name: "Panama Geisha")
        let grinder = GrinderProfile(name: "Weber Key", settingLabel: "4.4")
        let basket = BasketProfile(name: "20g VST", nominalDoseGrams: Decimal(string: "20")!)
        let recipe = try RecipeSnapshot(
            beanID: bean.id,
            grinderID: grinder.id,
            basketID: basket.id,
            doseGrams: Decimal(string: "20")!,
            targetYieldGrams: Decimal(string: "40")!,
            targetTimeSeconds: 28
        )

        let data = try JSONEncoder().encode(recipe)
        let decoded = try JSONDecoder().decode(RecipeSnapshot.self, from: data)

        #expect(decoded == recipe)
    }

    @Test("recipe snapshot decoding rejects a forged targetRatio")
    func recipeSnapshotDecodeRejectsForgedRatio() throws {
        let bean = BeanBag(name: "Forge Test")
        let grinder = GrinderProfile(name: "G", settingLabel: "1")
        let basket = BasketProfile(name: "B", nominalDoseGrams: 18)
        let recipe = try RecipeSnapshot(
            beanID: bean.id, grinderID: grinder.id, basketID: basket.id,
            doseGrams: 18, targetYieldGrams: 36, targetTimeSeconds: 30
        )
        var data = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(recipe)) as! [String: Any]
        var forgedRatio = data["targetRatio"] as! [String: Any]
        forgedRatio["value"] = 99
        data["targetRatio"] = forgedRatio
        let forgedData = try JSONSerialization.data(withJSONObject: data)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(RecipeSnapshot.self, from: forgedData)
        }
    }

    @Test("shot attempt round-trips through JSON")
    func shotAttemptCodableRoundTrip() throws {
        let bean = BeanBag(name: "Sumatra Mandheling")
        let grinder = GrinderProfile(name: "EK43", settingLabel: "7")
        let basket = BasketProfile(name: "18g", nominalDoseGrams: 18)
        let recipe = try RecipeSnapshot(
            beanID: bean.id, grinderID: grinder.id, basketID: basket.id,
            doseGrams: 18, targetYieldGrams: 36, targetTimeSeconds: 30
        )
        let observation = SensoryObservation(tasteVerdict: .balanced, flowVerdict: .onTarget, notes: [.balanced])
        let shot = try ShotAttempt(
            recipe: recipe, measuredYieldGrams: 36, elapsedSeconds: 29, firstDropSeconds: 6, observation: observation
        )

        let data = try JSONEncoder().encode(shot)
        let decoded = try JSONDecoder().decode(ShotAttempt.self, from: data)

        #expect(decoded == shot)
    }

    @Test("shot attempt decoding rejects negative elapsed seconds smuggled in JSON")
    func shotAttemptDecodeRejectsNegativeElapsed() throws {
        let bean = BeanBag(name: "Forge Test")
        let grinder = GrinderProfile(name: "G", settingLabel: "1")
        let basket = BasketProfile(name: "B", nominalDoseGrams: 18)
        let recipe = try RecipeSnapshot(
            beanID: bean.id, grinderID: grinder.id, basketID: basket.id,
            doseGrams: 18, targetYieldGrams: 36, targetTimeSeconds: 30
        )
        let shot = try ShotAttempt(recipe: recipe, measuredYieldGrams: 36, elapsedSeconds: 25, firstDropSeconds: nil, observation: .balanced)

        var data = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(shot)) as! [String: Any]
        data["elapsedSeconds"] = -5
        let forgedData = try JSONSerialization.data(withJSONObject: data)

        #expect(throws: ShotAttemptError.negativeElapsedSeconds) {
            _ = try JSONDecoder().decode(ShotAttempt.self, from: forgedData)
        }
    }

    @Test("bean bag round-trips through JSON")
    func beanBagCodableRoundTrip() throws {
        let bean = BeanBag(name: "Costa Rica Tarrazu", roastDate: Date(timeIntervalSince1970: 1_700_000_000))
        let data = try JSONEncoder().encode(bean)
        let decoded = try JSONDecoder().decode(BeanBag.self, from: data)
        #expect(decoded == bean)
    }

    @Test("grinder profile round-trips through JSON")
    func grinderProfileCodableRoundTrip() throws {
        let grinder = GrinderProfile(name: "Baratza Sette", settingLabel: "20")
        let data = try JSONEncoder().encode(grinder)
        let decoded = try JSONDecoder().decode(GrinderProfile.self, from: data)
        #expect(decoded == grinder)
    }

    @Test("basket profile round-trips through JSON")
    func basketProfileCodableRoundTrip() throws {
        let basket = BasketProfile(name: "21g VST", nominalDoseGrams: Decimal(string: "21")!)
        let data = try JSONEncoder().encode(basket)
        let decoded = try JSONDecoder().decode(BasketProfile.self, from: data)
        #expect(decoded == basket)
    }

    @Test("sensory observation round-trips through JSON")
    func sensoryObservationCodableRoundTrip() throws {
        let observation = SensoryObservation(tasteVerdict: .underExtracted, flowVerdict: .fast, notes: [.sour, .thin])
        let data = try JSONEncoder().encode(observation)
        let decoded = try JSONDecoder().decode(SensoryObservation.self, from: data)
        #expect(decoded == observation)
    }

    @Test("shot attempt validates non-negative timings")
    func shotAttemptTimingValidation() throws {
        let bean = BeanBag(name: "Colombia Huila")
        let grinder = GrinderProfile(name: "DF64", settingLabel: "16")
        let basket = BasketProfile(name: "18g VST", nominalDoseGrams: Decimal(string: "18")!)
        let recipe = try RecipeSnapshot(
            beanID: bean.id,
            grinderID: grinder.id,
            basketID: basket.id,
            doseGrams: Decimal(string: "18")!,
            targetYieldGrams: Decimal(string: "36")!,
            targetTimeSeconds: 30
        )

        #expect(throws: ShotAttemptError.negativeElapsedSeconds) {
            _ = try ShotAttempt(
                recipe: recipe,
                measuredYieldGrams: 36,
                elapsedSeconds: -1,
                firstDropSeconds: nil,
                observation: .balanced
            )
        }

        #expect(throws: ShotAttemptError.invalidFirstDrop) {
            _ = try ShotAttempt(
                recipe: recipe,
                measuredYieldGrams: 36,
                elapsedSeconds: 25,
                firstDropSeconds: 26,
                observation: .balanced
            )
        }
    }
}
