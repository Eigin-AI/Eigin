import Foundation
@preconcurrency import LiteRTLM

extension LocalClient {
    static func gemmaStatus() async -> LocalModelStatus {
        let state = await GemmaModelManager.shared.state
        switch state {
        case .notDownloaded:
            return LocalModelStatus(
                id: "gemma-4-e2b",
                displayName: Localized.Model.gemma4e2b,
                state: .notDownloaded
            )
        case .downloading(let info):
            return LocalModelStatus(
                id: "gemma-4-e2b",
                displayName: Localized.Model.gemma4e2b,
                state: .downloading(progress: info.fractionCompleted)
            )
        case .queued:
            return LocalModelStatus(
                id: "gemma-4-e2b",
                displayName: Localized.Model.gemma4e2b,
                state: .downloading(progress: 0)
            )
        case .downloaded, .preparing:
            return LocalModelStatus(
                id: "gemma-4-e2b",
                displayName: Localized.Model.gemma4e2b,
                state: .downloading(progress: 1.0)
            )
        case .ready:
            return LocalModelStatus(
                id: "gemma-4-e2b",
                displayName: Localized.Model.gemma4e2b,
                state: .ready
            )
        case .failed(let message):
            return LocalModelStatus(
                id: "gemma-4-e2b",
                displayName: Localized.Model.gemma4e2b,
                state: .unavailable(reason: message)
            )
        case .unavailable(let reason):
            return LocalModelStatus(
                id: "gemma-4-e2b",
                displayName: Localized.Model.gemma4e2b,
                state: .unavailable(reason: reason)
            )
        }
    }

    static func allLocalModelStatuses() async -> [LocalModelStatus] {
        var statuses = [LocalModelStatus]()
        await statuses.append(gemmaStatus())
        return statuses
    }
}
