import EiginSDK

/// Maps checkpoint values and restores app-owned message identities.
enum CheckpointSDKConversion {
    static func build(
        produced: [ChatMessage], retainedCount: Int, isDone: Bool,
        isExecutingTools: Bool, partialContent: String, currentMessageID: String
    ) -> [ChatMessage] {
        let progress = EiginSDK.Experimental.Agent.Progress(
            retainedCount: UInt64(retainedCount), isDone: isDone,
            isExecutingTools: isExecutingTools, partialContent: partialContent,
            currentMessageIndex: produced.firstIndex { $0.localID == currentMessageID }
                .map(UInt64.init)
        )
        return EiginSDK.Experimental.Agent.checkpoint(
            produced.map(MessagePreparationSDKConversion.message), progress: progress
        ).map { entry in
            switch entry.origin {
            case .produced(let index):
                MessagePreparationSDKConversion.restore(
                    .init(origin: .history(sourceIndex: index), message: entry.message),
                    history: produced
                )
            case .partialProse:
                RoundSDKConversion.message(entry.message, localID: currentMessageID)
            case .interruptedTool:
                RoundSDKConversion.message(entry.message)
            }
        }
    }
}
