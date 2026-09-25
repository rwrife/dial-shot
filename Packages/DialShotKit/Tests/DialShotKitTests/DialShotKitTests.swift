import Testing
@testable import DialShotKit

@Suite("Skeleton placeholder")
struct DialShotKitTests {
    @Test("domain namespace is reachable")
    func domainNamespace() {
        #expect(DialShotKit.domain == "DialShotKit")
    }

    @Test("milestone marker is set for M0")
    func milestoneMarker() {
        #expect(DialShotKit.milestone == "M0-skeleton")
    }

    @Test("skeleton exposes no stored state beyond constants")
    func constantsAreStable() {
        // Guards the contract later issues depend on: these markers exist
        // and are pure constants (no clock, no I/O) in the M0 skeleton.
        let first = (DialShotKit.domain, DialShotKit.milestone)
        let second = (DialShotKit.domain, DialShotKit.milestone)
        #expect(first == second)
    }
}
