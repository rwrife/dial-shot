import Foundation

/// The single permitted adjustment action. Grinder settings are user-authored
/// values scoped to a grinder; grind actions move the user's own setting, while
/// ratio actions adjust the yield target without asserting universal quality.
public enum AdjustmentAction: String, Codable, Equatable, Sendable {
    case grindFiner
    case grindCoarser
    case increaseYieldRatio
    case decreaseYieldRatio
}

/// Serializable identities of the bounded rule table. Each case names the
/// exact triggering evidence combination.
public enum AdjustmentRule: String, Codable, Equatable, CaseIterable, Sendable {
    case underExtractedFastFlow
    case underExtractedOnTargetFlow
    case overExtractedSlowFlow
    case overExtractedOnTargetFlow

    public var rationale: String {
        switch self {
        case .underExtractedFastFlow:
            "Under-extracted (sour) taste combined with a fast flow: grind one step finer to slow the flow and raise extraction."
        case .underExtractedOnTargetFlow:
            "Under-extracted (sour) taste with on-target flow: increase the target yield ratio slightly to raise extraction without changing grind."
        case .overExtractedSlowFlow:
            "Over-extracted (bitter) taste combined with a slow flow: grind one step coarser to speed the flow and lower extraction."
        case .overExtractedOnTargetFlow:
            "Over-extracted (bitter) taste with on-target flow: decrease the target yield ratio slightly to lower extraction without changing grind."
        }
    }
}

/// One concrete adjustment. The engine can only ever produce zero or one of
/// these, never a list.
public struct Adjustment: Codable, Equatable, Sendable {
    public let action: AdjustmentAction
    public let rule: AdjustmentRule
    public let rationale: String

    init(action: AdjustmentAction, rule: AdjustmentRule) {
        self.action = action
        self.rule = rule
        rationale = rule.rationale
    }
}

/// The engine's full result space: one adjustment, an explicit "no change",
/// or an explicit unknown. Unknown is a first-class state, never a silent
/// fallback to a guess.
public enum DialInSuggestion: Codable, Equatable, Sendable {
    case adjustment(Adjustment)
    case noChangeRecommended
    case insufficientEvidence(reason: String)

    public var isInsufficientEvidence: Bool {
        if case .insufficientEvidence = self { return true }
        return false
    }
}

/// Deterministic dial-in engine. Maps a shot's taste verdict plus flow
/// verdict through a fixed, precedence-free table:
///
/// | taste           | flow      | outcome                          |
/// |-----------------|-----------|----------------------------------|
/// | underExtracted  | fast      | adjust: grind finer              |
/// | underExtracted  | onTarget  | adjust: longer yield ratio       |
/// | overExtracted   | slow      | adjust: grind coarser            |
/// | overExtracted   | onTarget  | adjust: shorter yield ratio      |
/// | balanced        | onTarget  | no change recommended            |
/// | any other combo | —         | insufficient evidence (explicit) |
///
/// Missing verdicts always yield the explicit unknown state. At most one
/// adjustment is ever produced; conflicting evidence never resolves to a
/// direction.
public enum DialInEngine {
    public static func suggest(for shot: ShotAttempt) -> DialInSuggestion {
        let taste = shot.observation.tasteVerdict
        let flow = shot.observation.flowVerdict
        let notes = Set(shot.observation.notes)

        // Contradictory notes veto the main taste/flow rules: an under-extracted
        // verdict contradicted by a bitter/astringent note, or an over-extracted
        // verdict contradicted by a sour note, is conflicting evidence.
        if taste == .underExtracted && (notes.contains(.bitter) || notes.contains(.astringent)) {
            return .insufficientEvidence(
                reason: "Under-extracted taste verdict is contradicted by bitter/astringent notes; conflicting sensory evidence, so no adjustment is proposed."
            )
        }
        if taste == .overExtracted && notes.contains(.sour) {
            return .insufficientEvidence(
                reason: "Over-extracted taste verdict is contradicted by sour notes; conflicting sensory evidence, so no adjustment is proposed."
            )
        }
        if notes.contains(.sour) && notes.contains(.bitter) {
            return .insufficientEvidence(
                reason: "Simultaneously sour and bitter notes indicate channel-driven uneven extraction; conflicting evidence, so no adjustment is proposed."
            )
        }
        if (taste == .underExtracted || taste == .overExtracted) && notes.contains(.balanced) {
            return .insufficientEvidence(
                reason: "A non-balanced taste verdict is contradicted by a balanced note; conflicting evidence, so no adjustment is proposed."
            )
        }
        if taste == .balanced && (notes.contains(.sour) || notes.contains(.bitter) || notes.contains(.astringent)) {
            return .insufficientEvidence(
                reason: "A balanced taste verdict is contradicted by a sour/bitter/astringent note; conflicting evidence, so no change is confirmed."
            )
        }

        switch (taste, flow) {
        case (.underExtracted, .fast):
            return .adjustment(Adjustment(action: .grindFiner, rule: .underExtractedFastFlow))
        case (.underExtracted, .onTarget):
            return .adjustment(Adjustment(action: .increaseYieldRatio, rule: .underExtractedOnTargetFlow))
        case (.overExtracted, .slow):
            return .adjustment(Adjustment(action: .grindCoarser, rule: .overExtractedSlowFlow))
        case (.overExtracted, .onTarget):
            return .adjustment(Adjustment(action: .decreaseYieldRatio, rule: .overExtractedOnTargetFlow))
        case (.balanced, .onTarget):
            return .noChangeRecommended
        case (.underExtracted, .slow):
            return .insufficientEvidence(
                reason: "Under-extracted taste is not corroborated by the flow verdict; evidence is partial or conflicting, so no grind direction is proposed."
            )
        case (.overExtracted, .fast):
            return .insufficientEvidence(
                reason: "Over-extracted taste is not corroborated by the flow verdict; evidence is partial or conflicting, so no grind direction is proposed."
            )
        case (.balanced, .fast), (.balanced, .slow):
            return .insufficientEvidence(
                reason: "Taste reads balanced while flow is off target; conflicting evidence, so no change is proposed."
            )
        case (nil, _) where flow == nil:
            return .insufficientEvidence(
                reason: "No taste or flow observations recorded; insufficient evidence for any suggestion."
            )
        case (nil, _):
            return .insufficientEvidence(
                reason: "No taste verdict recorded; insufficient evidence for any suggestion."
            )
        case (_, nil):
            return .insufficientEvidence(
                reason: "No flow verdict recorded; insufficient evidence for any suggestion."
            )
        }
    }
}
