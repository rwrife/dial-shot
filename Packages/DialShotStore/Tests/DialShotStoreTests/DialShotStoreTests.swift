import Testing
import DialShotStore

@Suite("DialShotStore metadata")
struct DialShotStoreTests {
    @Test("domain identifier is DialShotStore")
    func domainIdentifier() {
        #expect(DialShotStore.domain == "DialShotStore")
    }
}
