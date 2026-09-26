import Testing
@testable import DialShotKit

@Suite("Skeleton placeholder")
struct DialShotKitTests {
    @Test("domain namespace is reachable")
    func domainNamespace() {
        #expect(DialShotKit.domain == "DialShotKit")
    }

    @Test("milestone marker is set for M1")
    func milestoneMarker() {
        #expect(DialShotKit.milestone == "M1-domain-engine")
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
