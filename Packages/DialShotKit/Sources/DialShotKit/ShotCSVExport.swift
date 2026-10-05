import Foundation

/// Issue #7 — flat CSV export of the shot log.
///
/// `ShotCSVExport` renders `HistoryShot` values into RFC 4180 CSV with the
/// exact header contract from the issue:
/// `date,bean,roast,grinder,setting,dose,yield,ratio,time,taste,adjustment`.
///
/// Determinism rules (quality contract):
/// - Rows sort by `createdAt`, then id, exactly like `ShotHistory.filter`.
/// - Dates use ISO 8601 (`yyyy-MM-dd'T'HH:mm:ss'Z'`, UTC) so exports are
///   locale-independent and re-importable.
/// - Decimals use `Decimal`'s canonical string (no float drift).
/// - Ratio uses the domain's `displayString` (1:x.y) — the same text the
///   app shows, never a silently re-rounded value.
/// - Missing evidence exports an explicit `unknown` token; it is never
///   guessed or left ambiguously blank except for genuinely absent free
///   text (setting, roast date).
/// - Fields containing commas, quotes, or newlines are quoted per RFC 4180.
public enum ShotCSVExport {
    public static let header = "date,bean,roast,grinder,setting,dose,yield,ratio,time,taste,adjustment"

    /// Explicit token for verdicts/adjustments the record does not contain.
    public static let unknownToken = "unknown"
    /// Explicit token for a setting the user never recorded.
    public static let notRecordedToken = "not recorded"

    public static func csv(_ shots: [HistoryShot]) -> String {
        let sorted = ShotHistory.filter(shots, using: HistoryFilter())
        var lines = [header]
        lines.append(contentsOf: sorted.map(row))
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    static func row(_ shot: HistoryShot) -> String {
        [
            iso8601(shot.attempt.createdAt),
            shot.beanName,
            shot.beanRoastDate.map(iso8601) ?? notRecordedToken,
            shot.grinderName,
            shot.grinderSetting ?? notRecordedToken,
            shot.attempt.recipe.doseGrams.description,
            shot.attempt.measuredYieldGrams.description,
            shot.attempt.brewRatio.displayString,
            "\(shot.attempt.elapsedSeconds)s",
            tasteText(shot.attempt.observation.tasteVerdict),
            adjustmentText(shot.suggestion),
        ].map(escape).joined(separator: ",")
    }

    static func tasteText(_ verdict: TasteVerdict?) -> String {
        switch verdict {
        case .underExtracted: "under-extracted"
        case .balanced: "balanced"
        case .overExtracted: "over-extracted"
        case nil: unknownToken
        }
    }

    /// The stored suggestion rendered verbatim from the rule table — an
    /// explainable memory aid naming the exact action, never a re-derived
    /// opinion. Missing suggestion exports `unknown`.
    static func adjustmentText(_ suggestion: DialInSuggestion?) -> String {
        switch suggestion {
        case .adjustment(let adjustment): adjustment.action.rawValue
        case .noChangeRecommended: "no change"
        case .insufficientEvidence: unknownToken
        case nil: unknownToken
        }
    }

    static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return formatter.string(from: date)
    }
}
