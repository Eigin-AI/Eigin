import Foundation
import Observation

/// Manages the app-wide language preference and persists the user's choice to `UserDefaults`.
@Observable
final class LanguageManager: @unchecked Sendable {
    var currentLanguage: AppLanguage

    init() {
        if let saved = UserDefaults.standard.string(forKey: StorageKey.appLanguage) {
            currentLanguage = AppLanguage(rawValue: saved) ?? .english
        } else {
            let detected = AppLanguage.detectedFromSystem() ?? .english
            currentLanguage = detected
            UserDefaults.standard.set(detected.rawValue, forKey: StorageKey.appLanguage)
        }
    }

    func setLanguage(_ language: AppLanguage) {
        currentLanguage = language
        UserDefaults.standard.set(language.rawValue, forKey: StorageKey.appLanguage)
    }
}

// MARK: - Bundle

extension Bundle {
    /// Returns the lproj bundle for the current app language, so `String(localized:bundle:)`
    /// resolves the correct translation at runtime even when the process locale differs.
    static var appLanguage: Bundle {
        let code = UserDefaults.standard.string(forKey: StorageKey.appLanguage) ?? "en"
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else {
            return Bundle.main
        }
        return bundle
    }
}
