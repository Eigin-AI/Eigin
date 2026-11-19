import EiginSDKBindings

public extension EiginSDK.Experimental {
    /// Transient reply and tool transcript handling; hosts execute operations.
    enum Agent {
        public typealias Turn = AgentTurn
        public typealias Action = TurnAction
        public typealias FinishReason = TurnFinishReason
        public typealias Signals = TurnSignals
        public typealias TurnFailure = EiginSDKBindings.TurnFailure
        public typealias Continuation = TurnContinuation
        public typealias TurnError = EiginSDKBindings.TurnError
        public typealias Round = AgentRound
        public typealias Outcome = RoundOutcome
        public typealias ToolResult = RoundToolResult
        public typealias Failure = RoundError
    }
}

public extension EiginSDK.Experimental.Agent {
    typealias Progress = CheckpointProgress
    typealias CheckpointEntry = CheckpointMessage
    typealias Origin = CheckpointOrigin

    /// Builds a transcript snapshot; the host owns saving and app message identities.
    static func checkpoint(
        _ produced: [EiginSDK.Experimental.Conversation.Message], progress: Progress
    ) -> [CheckpointEntry] {
        agentBuildCheckpoint(produced: produced, progress: progress)
    }
}
