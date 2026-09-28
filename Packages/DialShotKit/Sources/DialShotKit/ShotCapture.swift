import Foundation

/// A monotonic shot clock. Passing `at` makes each transition deterministic in tests;
/// live callers use the process uptime clock, which advances while the app is suspended.
public struct ShotTimer: Sendable {
    public enum Phase: Sendable { case idle, running, stopped }

    public private(set) var phase: Phase = .idle
    public private(set) var firstDropSeconds: Int?
    private var startedAt: TimeInterval = 0
    private var latestAt: TimeInterval = 0

    public init() {}

    public mutating func start(at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard phase == .idle else { return }
        startedAt = uptime
        latestAt = uptime
        phase = .running
    }

    @discardableResult
    public mutating func markFirstDrop(at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        guard phase == .running, firstDropSeconds == nil else { return false }
        firstDropSeconds = elapsedSeconds(at: uptime)
        return true
    }

    public mutating func stop(at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard phase == .running else { return }
        _ = elapsedSeconds(at: uptime)
        phase = .stopped
    }

    public mutating func elapsedSeconds(at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Int {
        guard phase != .idle else { return 0 }
        if phase == .running, uptime.isFinite {
            latestAt = max(latestAt, uptime)
        }
        return Int((latestAt - startedAt).rounded(.down))
    }
}

public enum ShotCaptureError: Error, Equatable, Sendable {
    case timerNotStopped
    case missingYield
}

public struct ShotReview: Sendable {
    public let attempt: ShotAttempt
    public let suggestion: DialInSuggestion
}

/// The unsaved capture draft. Review constructs the same immutable attempt and
/// engine result that will be stored, so the user can inspect both before save.
public struct ShotCapture: Sendable {
    public let recipe: RecipeSnapshot
    public private(set) var timer = ShotTimer()
    public var measuredYieldGrams: Decimal?
    public var notes: Set<SensoryNote> = []
    public var flowVerdict: FlowVerdict?

    public init(recipe: RecipeSnapshot) { self.recipe = recipe }

    public mutating func start(at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        timer.start(at: uptime)
    }

    @discardableResult
    public mutating func markFirstDrop(at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        timer.markFirstDrop(at: uptime)
    }

    public mutating func stop(at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        timer.stop(at: uptime)
    }

    public mutating func elapsedSeconds(at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Int {
        timer.elapsedSeconds(at: uptime)
    }

    public func review() throws -> ShotReview {
        guard timer.phase == .stopped else { throw ShotCaptureError.timerNotStopped }
        guard let measuredYieldGrams else { throw ShotCaptureError.missingYield }

        let taste: TasteVerdict?
        if notes.contains(.balanced) { taste = .balanced }
        else if notes.contains(.sour) { taste = .underExtracted }
        else if notes.contains(.bitter) || notes.contains(.astringent) { taste = .overExtracted }
        else { taste = nil }

        var frozenTimer = timer
        let attempt = try ShotAttempt(
            recipe: recipe,
            measuredYieldGrams: measuredYieldGrams,
            elapsedSeconds: frozenTimer.elapsedSeconds(),
            firstDropSeconds: timer.firstDropSeconds,
            observation: SensoryObservation(
                tasteVerdict: taste,
                flowVerdict: flowVerdict,
                notes: notes.sorted { $0.rawValue < $1.rawValue }
            )
        )
        return ShotReview(attempt: attempt, suggestion: DialInEngine.suggest(for: attempt))
    }
}
