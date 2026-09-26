import Foundation
import Testing
@testable import DialShotKit

@Suite("Brew ratio")
struct BrewRatioTests {
    @Test("formats exact decimal ratios consistently")
    func exactDisplay() throws {
        let ratio = try BrewRatio(doseGrams: Decimal(string: "18.0")!, yieldGrams: Decimal(string: "36.0")!)

        #expect(ratio.value == Decimal(string: "2")!)
        #expect(ratio.displayString == "1:2.0")
    }

    @Test("preserves decimal arithmetic without Double drift")
    func decimalArithmetic() throws {
        let ratio = try BrewRatio(doseGrams: Decimal(string: "18.1")!, yieldGrams: Decimal(string: "40.7")!)

        #expect(ratio.displayString == "1:2.2")
    }

    @Test("zero yield is a valid measurable ratio")
    func zeroYield() throws {
        let ratio = try BrewRatio(doseGrams: Decimal(string: "18")!, yieldGrams: 0)

        #expect(ratio.value == 0)
        #expect(ratio.displayString == "1:0.0")
    }

    @Test("zero dose is rejected instead of dividing by zero")
    func zeroDose() {
        #expect(throws: BrewRatioError.nonPositiveDose) {
            try BrewRatio(doseGrams: 0, yieldGrams: 36)
        }
    }

    @Test("negative yield is rejected")
    func negativeYield() {
        #expect(throws: BrewRatioError.negativeYield) {
            try BrewRatio(doseGrams: 18, yieldGrams: -1)
        }
    }

    @Test("rounding boundary: halves round up (18g : 36.9g -> 1:2.05 -> 1:2.1)")
    func roundingBoundaryHalfUp() throws {
        // 36.9 / 18 = 2.05, half-up rounding must format to 1:2.1, not 1:2.0
        let ratio = try BrewRatio(doseGrams: Decimal(string: "18.0")!, yieldGrams: Decimal(string: "36.9")!)
        #expect(ratio.displayString == "1:2.1")
    }

    @Test("decoding rejects payloads with zero dose")
    func decodeRejectsZeroDose() {
        let json = """
        {"doseGrams":0,"yieldGrams":36,"value":0}
        """.data(using: .utf8)!

        #expect(throws: BrewRatioError.nonPositiveDose) {
            _ = try JSONDecoder().decode(BrewRatio.self, from: json)
        }
    }

    @Test("decoding rejects payloads whose stored value disagrees with dose/yield")
    func decodeRejectsForgedValue() {
        let json = """
        {"doseGrams":18,"yieldGrams":36,"value":5}
        """.data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(BrewRatio.self, from: json)
        }
    }

    @Test("round-trips through JSON")
    func codableRoundTrip() throws {
        let original = try BrewRatio(doseGrams: Decimal(string: "17.5")!, yieldGrams: Decimal(string: "38.5")!)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BrewRatio.self, from: data)

        #expect(decoded == original)
        #expect(decoded.displayString == "1:2.2")
    }
}
