import Foundation

/// One-launch migration from the split pending keys (`pendingInitiativeID`,
/// `pendingOnboardingChat`) onto the unified ``PendingDestination`` store.
enum PendingDestinationMigrator {
    static func migrateLegacyKeys() {
        let defaults = UserDefaults.standard

        if let id = legacyUUID(StorageKey.pendingOnboardingChat) {
            PendingDestination.set(.chat(id))
            defaults.removeObject(forKey: StorageKey.pendingOnboardingChat)
        }

        if let id = legacyUUID("pendingInitiativeID") {
            PendingDestination.set(.initiative(id))
            defaults.removeObject(forKey: "pendingInitiativeID")
        }
    }

    private static func legacyUUID(_ key: String) -> UUID? {
        guard let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        return UUID(uuidString: raw)
    }
}
