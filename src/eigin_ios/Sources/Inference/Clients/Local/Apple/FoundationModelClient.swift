import Foundation
import FoundationModels

enum FoundationModelClientError: LocalizedError {
    case notAvailable

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            "Apple Intelligence is not available on this device."
        }
    }
}

enum FoundationModelClient {
    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            nil
        case .unavailable(.deviceNotEligible):
            Localized.Errors.AppleIntelligence.notSupported
        case .unavailable(.appleIntelligenceNotEnabled):
            Localized.Errors.AppleIntelligence.enableHint
        case .unavailable(.modelNotReady):
            Localized.Errors.AppleIntelligence.stillDownloading
        case .unavailable:
            Localized.Errors.AppleIntelligence.notAvailable
        }
    }
}
