import EiginSDK
import Foundation

/// Routes presentation only to the UI that owns this turn.
@MainActor
struct ChatTurnPresentationScope {
    weak var view: AgenticChatLoop?
    let token: UUID

    var active: AgenticChatLoop? {
        guard let current, current.acceptsTurnWork else { return nil }
        return current
    }

    var current: AgenticChatLoop? {
        guard let view, view.isCurrentOperation(token) else { return nil }
        return view
    }
}

extension ChatTurnHost: EiginSDK.Experimental.Agent.TurnPresentation {
    func observe(_ event: SDK.ChatEvent) async {
        await presentation?.current?.receive(event, host: self)
    }

    func finishToolProse(hasProse: Bool) async {
        await presentation?.current?.finishToolProse(hasProse: hasProse)
    }

    func beforeTool(_ call: EiginSDK.Experimental.Inference.ToolCall) async {
        await presentation?.current?.beforeTool(call)
    }

    func afterTool() {
        presentation?.current?.afterToolCall?()
    }

    func drain() async {
        await presentation?.current?.drain()
    }
}
