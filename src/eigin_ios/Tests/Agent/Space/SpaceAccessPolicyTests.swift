@testable import Eigin
import Foundation
import Testing

@Suite("SpaceAccessPolicy")
struct SpaceAccessPolicyTests {
    let spaceA = UUID()
    let spaceB = UUID()
    let spaceC = UUID()

    // MARK: - Global items

    @Test func globalItemVisibleFromGlobal() {
        let policy = SpaceAccessPolicy(currentSpaceID: nil, publicSpaceIDs: [])
        #expect(policy.canAccess(itemSpaceID: nil))
    }

    @Test func globalItemVisibleFromSpace() {
        let policy = SpaceAccessPolicy(currentSpaceID: spaceA, publicSpaceIDs: [])
        #expect(policy.canAccess(itemSpaceID: nil))
    }

    // MARK: - Own space

    @Test func ownSpaceItemVisibleFromOwnSpace() {
        let policy = SpaceAccessPolicy(currentSpaceID: spaceA, publicSpaceIDs: [])
        #expect(policy.canAccess(itemSpaceID: spaceA))
    }

    // MARK: - Public spaces

    @Test func publicSpaceItemVisibleFromGlobal() {
        let policy = SpaceAccessPolicy(currentSpaceID: nil, publicSpaceIDs: [spaceA])
        #expect(policy.canAccess(itemSpaceID: spaceA))
    }

    @Test func publicSpaceItemVisibleFromOtherSpace() {
        let policy = SpaceAccessPolicy(currentSpaceID: spaceB, publicSpaceIDs: [spaceA])
        #expect(policy.canAccess(itemSpaceID: spaceA))
    }

    // MARK: - Private spaces

    @Test func privateSpaceItemHiddenFromGlobal() {
        let policy = SpaceAccessPolicy(currentSpaceID: nil, publicSpaceIDs: [])
        #expect(!policy.canAccess(itemSpaceID: spaceA))
    }

    @Test func privateSpaceItemHiddenFromOtherSpace() {
        let policy = SpaceAccessPolicy(currentSpaceID: spaceB, publicSpaceIDs: [])
        #expect(!policy.canAccess(itemSpaceID: spaceA))
    }

    @Test func privateSpaceItemVisibleFromOwnSpace() {
        // Even if not in publicSpaceIDs, own space is always visible
        let policy = SpaceAccessPolicy(currentSpaceID: spaceA, publicSpaceIDs: [])
        #expect(policy.canAccess(itemSpaceID: spaceA))
    }

    // MARK: - Mixed scenarios

    @Test func mixedPublicAndPrivateSpaces() {
        // spaceA is public, spaceC is private, viewing from spaceB
        let policy = SpaceAccessPolicy(currentSpaceID: spaceB, publicSpaceIDs: [spaceA])
        #expect(policy.canAccess(itemSpaceID: nil)) // global
        #expect(policy.canAccess(itemSpaceID: spaceA)) // public
        #expect(policy.canAccess(itemSpaceID: spaceB)) // own
        #expect(!policy.canAccess(itemSpaceID: spaceC)) // private, not own
    }
}
