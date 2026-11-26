import EiginSDK
import Foundation

/// Maps SDK-owned output identities to stable app message identities.
@MainActor
final class TurnMessageMapping {
    typealias SDK = EiginSDK.Experimental.Agent
    private let prefix = UUID().uuidString
    private var drafts: [UInt64: String] = [:]

    func draft(_ id: UInt64, localID: String) {
        drafts[id] = localID
    }

    func messages(_ entries: [SDK.OutputEntry]) -> [ChatMessage] {
        entries.map(message)
    }

    private func message(_ entry: SDK.OutputEntry) -> ChatMessage {
        let localID: String = switch entry.origin {
        case .recorded(let id): drafts[id] ?? "\(prefix)-output-\(id)"
        case .interruptedTool(let index): "\(prefix)-interrupted-\(index)"
        }
        return MessagePreparationSDKConversion.restore(
            .init(origin: .supplied, message: entry.message), history: [], localID: localID
        )
    }
}
