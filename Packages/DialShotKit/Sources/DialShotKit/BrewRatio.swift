import Foundation

public enum BrewRatioError: Error, Codable, Equatable, Sendable {
    case nonPositiveDose
    case negativeYield
}

/// Exact decimal brew ratio. Input values remain decimal throughout the
/// calculation so display does not inherit binary floating-point drift.
public struct BrewRatio: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case doseGrams
        case yieldGrams
        case value
    }

    public let doseGrams: Decimal
    public let yieldGrams: Decimal
    public let value: Decimal

    public init(doseGrams: Decimal, yieldGrams: Decimal) throws {
        guard doseGrams > 0 else { throw BrewRatioError.nonPositiveDose }
        guard yieldGrams >= 0 else { throw BrewRatioError.negativeYield }

        self.doseGrams = doseGrams
        self.yieldGrams = yieldGrams
        value = NSDecimalNumber(decimal: yieldGrams)
            .dividing(by: NSDecimalNumber(decimal: doseGrams))
            .decimalValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let dose = try container.decode(Decimal.self, forKey: .doseGrams)
        let yield = try container.decode(Decimal.self, forKey: .yieldGrams)
        let decodedValue = try container.decode(Decimal.self, forKey: .value)

        try self.init(doseGrams: dose, yieldGrams: yield)

        if value != decodedValue {
            throw DecodingError.dataCorruptedError(
                forKey: .value,
                in: container,
                debugDescription: "BrewRatio payload value does not match dose/yield-derived value"
            )
        }
    }

    public var displayString: String {
        var source = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 1, .plain)

        var formatted = NSDecimalNumber(decimal: rounded).stringValue
        if formatted.contains(".") == false {
            formatted += ".0"
        }
        return "1:\(formatted)"
    }
}
