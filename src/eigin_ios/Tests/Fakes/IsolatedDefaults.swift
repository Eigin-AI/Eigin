import Foundation

extension UserDefaults {
    /// A throwaway store, so a test never reads or leaves state in the app's own.
    static func isolated() -> UserDefaults {
        UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    }
}
