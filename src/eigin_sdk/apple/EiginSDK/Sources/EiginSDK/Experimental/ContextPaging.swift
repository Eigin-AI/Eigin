import EiginSDKBindings

public extension EiginSDK.Experimental.Context {
    /// Selection over the supplied history; the host persists stable identities separately.
    struct PageSelection: Sendable, Equatable {
        public let retainedStart: Int
        public let maskedResultIndices: [Int]

        /// Creates a previous selection. Indices must be ordered and input-local.
        public init(retainedStart: Int = 0, maskedResultIndices: [Int] = []) {
            self.retainedStart = retainedStart
            self.maskedResultIndices = maskedResultIndices
        }
    }

    /// Input budgets after reserving output space.
    struct PagingPolicy: Sendable {
        public let triggerTokens: Int
        public let targetTokens: Int
        public let maximumTokens: Int
        public let minimumRecentTurns: Int

        /// Creates explicit budgets; target < trigger <= maximum is required.
        public init(
            triggerTokens: Int,
            targetTokens: Int,
            maximumTokens: Int,
            minimumRecentTurns: Int = 2
        ) {
            self.triggerTokens = triggerTokens
            self.targetTokens = targetTokens
            self.maximumTokens = maximumTokens
            self.minimumRecentTurns = minimumRecentTurns
        }
    }

    /// Request-local edits and their estimated input cost.
    struct PagingResult: Sendable, Equatable {
        public let selection: PageSelection
        public let estimatedTokens: Int
        public let changed: Bool
    }

    /// Paging input is inconsistent, or protected material cannot fit.
    enum PagingError: Error, Sendable {
        case invalidInput
        case protectedContentTooLarge
    }

    /// Derives default paging budgets from the model's context and output ceilings.
    static func defaultPagingPolicy(contextWindow: Int, maxOutput: Int) -> PagingPolicy {
        let value = EiginSDKBindings.defaultPagingPolicy(
            contextWindow: Int64(contextWindow), maxOutput: Int64(maxOutput)
        )
        return PagingPolicy(
            triggerTokens: Int(value.triggerTokens), targetTokens: Int(value.targetTokens),
            maximumTokens: Int(value.maximumTokens), minimumRecentTurns: Int(value.minimumRecentTurns)
        )
    }

    /// Selects tool-result masks and whole-turn eviction without owning mutable state.
    /// Supply conversation history only; account for system/schema costs as fixed input.
    static func page(
        messages: [Message],
        previous: PageSelection = PageSelection(),
        policy: PagingPolicy,
        fixedInputTokens: Int = 0,
        protectedRanges: [Range<Int>] = []
    ) throws -> PagingResult {
        guard previous.retainedStart >= 0,
              previous.maskedResultIndices.allSatisfy({ $0 >= 0 }),
              policy.minimumRecentTurns >= 0,
              protectedRanges.allSatisfy({ $0.lowerBound >= 0 })
        else { throw PagingError.invalidInput }
        do {
            let result = try EiginSDKBindings.pageContext(input: ContextPagingInput(
                messages: messages.map(\.binding),
                previous: ContextPageSelection(
                    retainedStart: UInt64(previous.retainedStart),
                    maskedResultIndices: previous.maskedResultIndices.map(UInt64.init)
                ),
                policy: ContextPagingPolicy(
                    triggerTokens: Int64(policy.triggerTokens),
                    targetTokens: Int64(policy.targetTokens),
                    maximumTokens: Int64(policy.maximumTokens),
                    minimumRecentTurns: UInt64(policy.minimumRecentTurns)
                ),
                fixedInputTokens: Int64(fixedInputTokens),
                protectedRanges: protectedRanges.map {
                    ContextProtectedRange(start: UInt64($0.lowerBound), end: UInt64($0.upperBound))
                }
            ))
            return PagingResult(
                selection: PageSelection(
                    retainedStart: Int(result.selection.retainedStart),
                    maskedResultIndices: result.selection.maskedResultIndices.map(Int.init)
                ),
                estimatedTokens: Int(result.estimatedTokens),
                changed: result.changed
            )
        } catch ContextPagingError.InvalidInput {
            throw PagingError.invalidInput
        } catch ContextPagingError.ProtectedContentTooLarge {
            throw PagingError.protectedContentTooLarge
        }
    }
}
