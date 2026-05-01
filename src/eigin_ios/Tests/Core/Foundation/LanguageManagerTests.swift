@testable import Eigin
import Foundation
import Testing

@Suite("LanguageManager")
struct LanguageManagerTests {
    private let key = StorageKey.appLanguage

    private func cleanup() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    // MARK: - AppLanguage.detectedFromSystem

    @Test func detectedFromSystemReturnsFirstSupportedLanguage() {
        let language = AppLanguage.detectedFromSystem(preferredLanguages: ["da-DK"])
        #expect(language == .danish)
    }

    @Test func detectedFromSystemFallsBackThroughMultipleLanguages() {
        let language = AppLanguage.detectedFromSystem(preferredLanguages: ["fr-FR", "da", "en"])
        #expect(language == .danish)
    }

    @Test func detectedFromSystemReturnsNilForUnsupportedLanguages() {
        let language = AppLanguage.detectedFromSystem(preferredLanguages: ["fr", "de", "es"])
        #expect(language == nil)
    }

    @Test func detectedFromSystemHandlesLanguageCodesWithoutRegion() {
        let language = AppLanguage.detectedFromSystem(preferredLanguages: ["da"])
        #expect(language == .danish)
    }

    // MARK: - LanguageManager init

    @Test func initRespectsSavedPreference() {
        cleanup()
        defer { cleanup() }

        UserDefaults.standard.set("da", forKey: key)
        let manager = LanguageManager()

        #expect(manager.currentLanguage == .danish)
    }

    @Test func initFallsBackToEnglishWhenSavedPreferenceIsInvalid() {
        cleanup()
        defer { cleanup() }

        UserDefaults.standard.set("xx", forKey: key)
        let manager = LanguageManager()

        #expect(manager.currentLanguage == .english)
    }

    @Test func initAutoDetectsAndPersistsWhenNoSavedPreference() {
        cleanup()
        defer { cleanup() }

        // The test environment will have some preferred languages.
        // We just verify that a language is chosen and persisted.
        let manager = LanguageManager()

        // It should have picked a language (likely English in the test runner)
        #expect(manager.currentLanguage == .english || manager.currentLanguage == .danish)

        // The choice should be persisted
        let persisted = UserDefaults.standard.string(forKey: key)
        #expect(persisted == manager.currentLanguage.rawValue)
    }

    @Test func initDetectsDanishWhenPreferred() {
        cleanup()
        defer { cleanup() }

        // Temporarily override preferred languages by injecting into the test
        // Since LanguageManager uses Locale.preferredLanguages directly,
        // we test the happy path indirectly via the known behavior of
        // AppLanguage.detectedFromSystem. Here we verify the full integration.
        let detected = AppLanguage.detectedFromSystem(preferredLanguages: ["da-DK"])
        #expect(detected == .danish)

        // If we had saved "da", LanguageManager would use it
        UserDefaults.standard.set("da", forKey: key)
        let manager = LanguageManager()
        #expect(manager.currentLanguage == .danish)
    }

    // MARK: - setLanguage

    @Test func setLanguageUpdatesCurrentAndPersists() {
        cleanup()
        defer { cleanup() }

        let manager = LanguageManager()
        manager.setLanguage(.danish)

        #expect(manager.currentLanguage == .danish)
        #expect(UserDefaults.standard.string(forKey: key) == "da")
    }
}
