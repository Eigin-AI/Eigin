@testable import Eigin
import Foundation
import Testing

@Suite("KeychainService")
struct KeychainServiceTests {
    private let testServiceKey = "test.service.\(UUID().uuidString)"

    @Test func providerKeyFormat() {
        let service = DefaultKeychainService(serviceKey: testServiceKey)
        let id = UUID()
        let key = service.providerKey(for: id)
        #expect(key == "\(testServiceKey).provider.\(id.uuidString)")
    }

    @Test func saveAndReadRoundTrip() {
        let service = DefaultKeychainService(serviceKey: testServiceKey)
        let key = "test.roundtrip.\(UUID().uuidString)"
        defer { service.delete(key: key) }

        service.save(key: key, value: "secret123")
        #expect(service.read(key: key) == "secret123")
    }

    @Test func deleteRemovesValue() {
        let service = DefaultKeychainService(serviceKey: testServiceKey)
        let key = "test.delete.\(UUID().uuidString)"

        service.save(key: key, value: "toDelete")
        service.delete(key: key)
        #expect(service.read(key: key) == nil)
    }

    @Test func saveOverwritesExistingValue() {
        let service = DefaultKeychainService(serviceKey: testServiceKey)
        let key = "test.overwrite.\(UUID().uuidString)"
        defer { service.delete(key: key) }

        service.save(key: key, value: "first")
        service.save(key: key, value: "second")
        #expect(service.read(key: key) == "second")
    }
}
