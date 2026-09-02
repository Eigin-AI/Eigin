@testable import Eigin
import Foundation
import Testing

/// The time-left text must stay short: coarse units only, rounded up, and nil
/// while there's no estimate.
///
/// The suite pins the app language to English: `Localized` resolves through
/// the saved app-language lproj, so exact-string assertions would otherwise
/// fail under the Danish setting.
struct AssetRowTimeTextTests {
    /// Run `body` with English as the app's stored language.
    private func withEnglish(_ body: () -> Void) {
        let key = StorageKey.appLanguage
        let previous = UserDefaults.standard.string(forKey: key)
        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        body()
    }

    @Test func secondsStaySecondsUnderAMinute() {
        withEnglish {
            #expect(AssetRow.timeLeftText(1) == "1 s left")
            #expect(AssetRow.timeLeftText(42.4) == "43 s left")
        }
    }

    @Test func minuteRangesRoundUp() {
        withEnglish {
            #expect(AssetRow.timeLeftText(89) == "2 min left")
            #expect(AssetRow.timeLeftText(2400) == "40 min left")
            #expect(AssetRow.timeLeftText(5000) == "1 h 24 min left")
        }
    }

    @Test func hoursCompact() {
        withEnglish {
            #expect(AssetRow.timeLeftText(5400) == "1 h 30 min left")
        }
    }

    @Test func nilAndSubSecondHideTheEstimate() {
        #expect(AssetRow.timeLeftText(nil) == nil)
        #expect(AssetRow.timeLeftText(0) == nil)
        #expect(AssetRow.timeLeftText(0.4) == nil)
    }
}
