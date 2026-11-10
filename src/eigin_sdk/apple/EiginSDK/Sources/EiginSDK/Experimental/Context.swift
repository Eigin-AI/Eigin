import EiginSDKBindings

public extension EiginSDK.Experimental {
    /// Low-level context helpers. Prefer SDK chat orchestration when available.
    enum Context {}
}

public extension EiginSDK.Experimental.Context {
    /// Tool-call fields included in context sizing.
    struct ToolCall: Sendable {
        /// Function name.
        public let name: String
        /// Serialized function arguments.
        public let arguments: String

        /// Creates tool-call sizing facts.
        public init(name: String, arguments: String) {
            self.name = name
            self.arguments = arguments
        }
    }

    /// Portable message facts; reasoning validity is resolved by the host.
    struct Message: Sendable {
        /// API role; user messages delimit turns.
        public let role: String
        /// Visible message content.
        public let content: String?
        /// Optional sender name.
        public let name: String?
        /// Calls included in this message.
        public let toolCalls: [ToolCall]
        /// Token contribution from host-validated reasoning.
        public let additionalInputTokens: Int64
        /// Any reasoning history, even when invalid, blocks partial truncation.
        public let hasReasoningHistory: Bool

        /// Creates message facts without transferring ownership of host messages.
        public init(
            role: String,
            content: String? = nil,
            name: String? = nil,
            toolCalls: [ToolCall] = [],
            additionalInputTokens: Int64 = 0,
            hasReasoningHistory: Bool = false
        ) {
            self.role = role
            self.content = content
            self.name = name
            self.toolCalls = toolCalls
            self.additionalInputTokens = additionalInputTokens
            self.hasReasoningHistory = hasReasoningHistory
        }

        fileprivate var binding: ContextMessage {
            ContextMessage(
                role: role,
                content: content,
                name: name,
                toolCalls: toolCalls.map { ContextToolCall(
                    name: $0.name,
                    arguments: $0.arguments
                ) },
                additionalInputTokens: additionalInputTokens,
                hasReasoningHistory: hasReasoningHistory
            )
        }
    }

    /// Selected suffix and optional first-message content replacement.
    struct Selection: Sendable {
        /// Suffix start; the input message count denotes an empty selection.
        public let startIndex: Int
        /// Replacement content for the first selected message, when partial.
        public let partialContent: String?

        fileprivate init(_ binding: ContextSelection) {
            startIndex = Int(binding.startIndex)
            partialContent = binding.partialContent
        }
    }

    /// A usable summary or host-loggable rejection.
    enum SummaryResult: Sendable, Equatable {
        /// A usable tagged summary.
        case accepted(String)
        /// No exact opening tag; includes the trimmed grapheme count for logging.
        case missingOpeningTag(trimmedLength: UInt64)
        /// The trimmed body contains fewer than 50 grapheme clusters.
        case tooShort(bodyLength: UInt64)
    }

    /// Estimates text using grapheme clusters.
    static func estimate(_ text: String) -> Int {
        Int(EiginSDKBindings.estimateText(text: text))
    }

    /// Estimates message framing, content, tools, and reasoning.
    static func estimate(messages: [Message]) -> Int {
        Int(EiginSDKBindings.estimateMessages(messages: messages.map(\.binding)))
    }

    /// Estimates tool definitions at a fixed cost per tool. The count must be nonnegative.
    static func estimate(toolCount: Int) -> Int {
        Int(EiginSDKBindings.estimateTools(toolCount: UInt64(toolCount)))
    }

    /// Estimates a request including tool definitions. The tool count must be nonnegative.
    static func estimateRequest(messages: [Message], toolCount: Int) -> Int {
        Int(EiginSDKBindings.estimateRequest(
            messages: messages.map(\.binding),
            toolCount: UInt64(toolCount)
        ))
    }

    /// Selects whole newest turns, retaining the minimum beyond budget.
    static func retainedTail(
        messages: [Message],
        tokenBudget: Int,
        minimumTurns: Int = 2
    ) -> Selection {
        Selection(EiginSDKBindings.retainedTail(
            messages: messages.map(\.binding),
            tokenBudget: Int64(tokenBudget),
            minimumTurns: Int64(minimumTurns)
        ))
    }

    /// Selects a budgeted suffix with optional partial first message.
    static func truncateForBudget(messages: [Message], tokenBudget: Int) -> Selection {
        Selection(EiginSDKBindings.truncateForBudget(
            messages: messages.map(\.binding),
            tokenBudget: Int64(tokenBudget)
        ))
    }

    /// Selects a whole-message suffix with window hysteresis.
    static func windowedForBudget(messages: [Message], highMark: Int, lowMark: Int) -> Selection {
        Selection(EiginSDKBindings.windowedForBudget(
            messages: messages.map(\.binding),
            highMark: Int64(highMark),
            lowMark: Int64(lowMark)
        ))
    }

    /// Parses tagged summaries, accepting a missing closing tag.
    static func parseSummary(_ raw: String) -> SummaryResult {
        switch EiginSDKBindings.parseSummary(raw: raw) {
        case let .accepted(summary): .accepted(summary)
        case let .missingOpeningTag(trimmedLength): .missingOpeningTag(trimmedLength: trimmedLength)
        case let .tooShort(bodyLength): .tooShort(bodyLength: bodyLength)
        }
    }
}
