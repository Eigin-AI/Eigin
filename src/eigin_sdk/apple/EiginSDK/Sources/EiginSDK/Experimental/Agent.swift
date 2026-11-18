import EiginSDKBindings

public extension EiginSDK.Experimental {
    /// Transient reply and tool transcript handling; hosts own execution and orchestration.
    enum Agent {
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
