import Foundation
import Testing
import GRDB
@testable import DialShotStore

/// One-shot fixture generator, gated behind an environment variable so it
/// never runs as part of the normal test suite. Regenerate the committed
/// fixture (after an intentional, reviewed schema/seed change) with:
///
///   GENERATE_DIALSHOT_FIXTURE=1 swift test --filter FixtureGeneration
@Suite("Fixture generation (opt-in maintenance)")
struct FixtureGenerationTests {
    @Test("writes the committed v1 fixture database when explicitly requested")
    func generateFixture() throws {
        guard ProcessInfo.processInfo.environment["GENERATE_DIALSHOT_FIXTURE"] == "1" else {
            return
        }

        let fixturesDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
        try FileManager.default.createDirectory(at: fixturesDir, withIntermediateDirectories: true)
        let fixtureURL = fixturesDir.appendingPathComponent("v1_fixture.sqlite")
        try? FileManager.default.removeItem(at: fixtureURL)

        let queue = try DialShotDatabaseFactory.makeQueue(path: fixtureURL.path)
        try StoreFixture.seed(queue)

        #expect(FileManager.default.fileExists(atPath: fixtureURL.path))
    }
}
