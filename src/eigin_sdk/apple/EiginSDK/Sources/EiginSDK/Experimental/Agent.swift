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
