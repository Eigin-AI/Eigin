import Foundation

protocol PendingState {
    static var userDefaultsKey: String { get }

    static func set(_ id: UUID)
    static func get() -> UUID?
    static var any: Bool { get }
    static func clear()
}

extension PendingState {
    static func set(_ id: UUID) {
        UserDefaults.standard.set(id.uuidString, forKey: userDefaultsKey)
    }

    static func get() -> UUID? {
        guard let idString = UserDefaults.standard.string(forKey: userDefaultsKey) else {
            return nil
        }
        return UUID(uuidString: idString)
    }

    static var any: Bool {
        UserDefaults.standard.string(forKey: userDefaultsKey) != nil
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
}

enum PendingInitiative: PendingState {
    static let userDefaultsKey = "pendingInitiativeID"
}
