@testable import Eigin
import XCTest

final class PendingDestinationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PendingDestination.clear()
        UserDefaults.standard.removeObject(forKey: StorageKey.pendingOnboardingChat)
        UserDefaults.standard.removeObject(forKey: "pendingInitiativeID")
    }

    func testRoundTripsEveryCase() {
        let id = UUID()
        let cases: [PendingDestination] = [
            .initiative(id),
            .chat(id),
            .newChat(.newChat),
            .newChat(.dictationChat),
            .newChat(.liveCallChat),
        ]
        for destination in cases {
            PendingDestination.set(destination)
            XCTAssertEqual(PendingDestination.get(), destination)
        }
    }

    func testLastWriteWins() {
        PendingDestination.set(.newChat(.newChat))
        PendingDestination.set(.chat(UUID()))
        XCTAssertEqual(PendingDestination.get()?.chatUUID != nil, true)
        if case .newChat = PendingDestination.get() {
            XCTFail("expected chat destination to win")
        }
    }

    func testClear() {
        PendingDestination.set(.newChat(.liveCallChat))
        PendingDestination.clear()
        XCTAssertNil(PendingDestination.get())
    }

    func testIgnoresMalformedValue() {
        UserDefaults.standard.set("not-a-tagged-value", forKey: PendingDestination.storageKey)
        XCTAssertNil(PendingDestination.get())
        UserDefaults.standard.set("route:not-a-route", forKey: PendingDestination.storageKey)
        XCTAssertNil(PendingDestination.get())
    }

    func testLegacyKeysRemapOntoStore() {
        let chatID = UUID()
        UserDefaults.standard.set(chatID.uuidString, forKey: StorageKey.pendingOnboardingChat)
        let requestID = UUID()
        UserDefaults.standard.set(requestID.uuidString, forKey: "pendingInitiativeID")

        PendingDestinationMigrator.migrateLegacyKeys()

        XCTAssertEqual(PendingDestination.get(), .initiative(requestID))
        XCTAssertNil(UserDefaults.standard.string(forKey: StorageKey.pendingOnboardingChat))
        XCTAssertNil(UserDefaults.standard.string(forKey: "pendingInitiativeID"))
    }
}

private extension PendingDestination {
    var chatUUID: UUID? {
        if case .chat(let id) = self { return id }
        return nil
    }
}
