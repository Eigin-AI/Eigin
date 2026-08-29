import Foundation

/// Manages a sliding window over persisted messages for paginated display.
///
/// Uses a **render-weight budget** instead of fixed message counts. Heavy messages
/// (long text, code blocks, math) cost more weight, so the window automatically
/// shrinks for expensive content and expands for light conversations.
/// Tool-only assistant messages and `role:"tool"` results are free (weight 0).
/// Trimming never splits a tool group (assistant with toolCalls + subsequent tool messages).
@Observable @MainActor
final class MessageWindow {
    let pageBudget: Int
    let maxBudget: Int
    let minMessages: Int

    var messages: [ChatMessage] = []
    var allPersisted: [Message] = []
    var windowStartIndex: Int = 0
    var isPreloaded = false
    private(set) var isPaginating = false

    /// Set by the scroll view layer. When false, trimming is deferred.
    var isUserAtBottom = true

    var hasOlderMessages: Bool {
        isPreloaded && windowStartIndex > 0
    }

    var hasNewerMessages: Bool {
        guard isPreloaded else { return false }
        return windowStartIndex + messages.count < allPersisted.count
    }

    init(pageBudget: Int = 30, maxBudget: Int = 60, minMessages: Int = 5) {
        self.pageBudget = pageBudget
        self.maxBudget = maxBudget
        self.minMessages = minMessages
    }

    // MARK: - Content-aware helpers

    private func isContentMessage(_ message: Message) -> Bool {
        let cm = message.toChatMessage()
        if cm.role == "tool" { return false }
        if cm.role == "assistant", cm.content == nil || cm.content!.isEmpty { return false }
        return cm.content != nil && !cm.content!.isEmpty
    }

    private func isContentChatMessage(_ cm: ChatMessage) -> Bool {
        if cm.role == "tool" { return false }
        if cm.role == "assistant", cm.content == nil || cm.content!.isEmpty { return false }
        return cm.content != nil && !cm.content!.isEmpty
    }

    /// Count content messages in a ChatMessage array.
    private func contentCount(in messages: [ChatMessage]) -> Int {
        messages.count(where: { isContentChatMessage($0) })
    }

    // MARK: - Render weight

    /// Estimates the render cost of a single message without actually rendering it.
    /// Non-content messages (tool role, empty assistant) score 0.
    func weight(of message: ChatMessage) -> Int {
        guard isContentChatMessage(message) else { return 0 }
        guard let text = message.content else { return 0 }

        var w = 1 // base cost
        w += text.count / 200 // per 200 chars
        // Fenced code blocks
        var searchStart = text.startIndex
        while let range = text.range(of: "```", range: searchStart ..< text.endIndex) {
            w += 2
            searchStart = range.upperBound
        }
        // Math blocks: $$ or \[
        searchStart = text.startIndex
        while let range = text.range(of: "$$", range: searchStart ..< text.endIndex) {
            w += 2
            searchStart = range.upperBound
        }
        searchStart = text.startIndex
        while let range = text.range(of: "\\[", range: searchStart ..< text.endIndex) {
            w += 2
            searchStart = range.upperBound
        }
        // Large content bonus
        if text.count > 2000 { w += 3 }
        return w
    }

    /// Sum of render weights for all content messages.
    func totalWeight(of messages: [ChatMessage]) -> Int {
        messages.reduce(0) { $0 + weight(of: $1) }
    }

    /// Walks backwards from `from` accumulating render weight until `budget` is reached,
    /// guaranteeing at least `minMessages` content messages are included.
    private func walkBackForBudget(in messages: [Message], from: Int, budget: Int) -> Int {
        var accumulated = 0
        var contentSeen = 0
        var i = from - 1
        while i >= 0 {
            let cm = messages[i].toChatMessage()
            let w = weight(of: cm)
            if isContentChatMessage(cm) {
                contentSeen += 1
            }
            accumulated += w
            if accumulated >= budget, contentSeen >= minMessages {
                break
            }
            i -= 1
        }
        return max(0, i)
    }

    private enum TrimDirection {
        case fromStart
        case fromEnd
    }

    /// Adjust a trim index to avoid splitting a tool group.
    /// A tool group is: an assistant message with toolCalls + all subsequent role:"tool" messages.
    private func safeTrimIndex(
        in messages: [ChatMessage],
        target: Int,
        direction: TrimDirection
    ) -> Int {
        guard target > 0, target < messages.count else { return target }

        switch direction {
        case .fromStart:
            // Trimming first `target` messages. If target lands inside a tool group, move forward.
            var i = target
            while i < messages.count, messages[i].role == "tool" {
                i += 1
            }
            // Also check if we're landing on a tool-only assistant that starts a group
            if i < messages.count, messages[i].role == "assistant",
               messages[i].content == nil || messages[i].content!.isEmpty,
               messages[i].toolCalls != nil, !messages[i].toolCalls!.isEmpty
            {
                // We're at the start of a tool group — this is fine, include it
            }
            return i

        case .fromEnd:
            // Keeping first `target` messages. If the boundary splits a tool group, pull back.
            var i = target
            // If the message at index `i` (first excluded) is a tool message, pull back
            while i > 0, messages[i - 1].role == "tool" {
                i -= 1
            }
            // If we pulled back to a tool-only assistant, exclude it too
            if i > 0, messages[i - 1].role == "assistant",
               messages[i - 1].content == nil || messages[i - 1].content!.isEmpty,
               messages[i - 1].toolCalls != nil, !messages[i - 1].toolCalls!.isEmpty
            {
                i -= 1
            }
            return i
        }
    }

    /// Safe trim index operating on persisted Message array.
    private func safeTrimIndexPersisted(
        in messages: [Message],
        target: Int,
        direction: TrimDirection
    ) -> Int {
        guard target > 0, target < messages.count else { return target }
        let chatMessages = messages.map { $0.toChatMessage() }
        return safeTrimIndex(in: chatMessages, target: target, direction: direction)
    }

    // MARK: - Pagination

    func loadInitialWindow() -> [ChatMessage] {
        guard !allPersisted.isEmpty else { return [] }
        let start = walkBackForBudget(
            in: allPersisted,
            from: allPersisted.count,
            budget: pageBudget
        )
        let safeStart = safeTrimIndexPersisted(
            in: allPersisted,
            target: start,
            direction: .fromStart
        )
        windowStartIndex = safeStart
        return Array(allPersisted[safeStart...]).map { $0.toChatMessage() }
    }

    func loadOlderMessages() {
        guard isPreloaded, windowStartIndex > 0, !isPaginating else { return }
        isPaginating = true

        // Walk back from windowStartIndex for pageBudget worth of render weight
        let rawStart = walkBackForBudget(
            in: allPersisted,
            from: windowStartIndex,
            budget: pageBudget
        )
        let batchStart = safeTrimIndexPersisted(
            in: allPersisted,
            target: rawStart,
            direction: .fromStart
        )

        let batch = allPersisted[batchStart ..< windowStartIndex].map { $0.toChatMessage() }
        let beforeCount = messages.count
        messages.insert(contentsOf: batch, at: 0)
        windowStartIndex = batchStart

        // Trim from tail if total weight exceeds maxBudget (respecting minMessages floor).
        // Keep maxBudget worth from the head so the user's previous scroll position survives.
        if totalWeight(of: messages) > maxBudget, contentCount(in: messages) > minMessages {
            var accumulated = 0
            var contentSeen = 0
            var cutoff = messages.count
            for j in 0 ..< messages.count {
                let w = weight(of: messages[j])
                accumulated += w
                if isContentChatMessage(messages[j]) { contentSeen += 1 }
                if accumulated >= maxBudget, contentSeen >= minMessages {
                    cutoff = j + 1
                    break
                }
            }
            // Walk cutoff forward to include the rest of any tool group
            while cutoff < messages.count, messages[cutoff].role == "tool" {
                cutoff += 1
            }
            let removeCount = messages.count - cutoff
            if removeCount > 0 {
                messages.removeLast(removeCount)
            }
            AppLogger.debug(
                "loadOlder: prepended \(public: batch.count), trimmed \(public: removeCount) from tail, window=\(public: windowStartIndex)..<\(public: windowStartIndex + messages.count) of \(public: allPersisted.count), messages=\(public: beforeCount)→\(public: messages.count)",
                category: .chat
            )
        } else {
            AppLogger.debug(
                "loadOlder: prepended \(public: batch.count), window=\(public: windowStartIndex)..<\(public: windowStartIndex + messages.count) of \(public: allPersisted.count), messages=\(public: beforeCount)→\(public: messages.count)",
                category: .chat
            )
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isPaginating = false
        }
    }

    func loadNewerMessages() {
        guard isPreloaded, !isPaginating else { return }
        let windowEnd = windowStartIndex + messages.count
        guard windowEnd < allPersisted.count else { return }
        isPaginating = true

        // Walk forward from windowEnd accumulating pageBudget worth of weight
        var accumulated = 0
        var contentSeen = 0
        var batchEnd = windowEnd
        while batchEnd < allPersisted.count {
            let cm = allPersisted[batchEnd].toChatMessage()
            let w = weight(of: cm)
            if isContentChatMessage(cm) { contentSeen += 1 }
            accumulated += w
            batchEnd += 1
            if accumulated >= pageBudget, contentSeen >= minMessages { break }
        }
        // Include any trailing tool messages in the last group
        while batchEnd < allPersisted.count {
            let cm = allPersisted[batchEnd].toChatMessage()
            if cm.role == "tool" {
                batchEnd += 1
            } else {
                break
            }
        }

        let batch = allPersisted[windowEnd ..< batchEnd].map { $0.toChatMessage() }
        messages.append(contentsOf: batch)

        // Trim from head if total weight exceeds maxBudget (respecting minMessages floor).
        // Keep maxBudget worth from the tail so the user's previous scroll position survives.
        if totalWeight(of: messages) > maxBudget, contentCount(in: messages) > minMessages {
            var accumulated = 0
            var contentKept = 0
            var trimTarget = 0
            for j in stride(from: messages.count - 1, through: 0, by: -1) {
                accumulated += weight(of: messages[j])
                if isContentChatMessage(messages[j]) { contentKept += 1 }
                if accumulated >= maxBudget, contentKept >= minMessages {
                    trimTarget = j
                    break
                }
            }
            let safeTrim = safeTrimIndex(in: messages, target: trimTarget, direction: .fromStart)
            if safeTrim > 0 {
                messages.removeFirst(safeTrim)
                windowStartIndex += safeTrim
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isPaginating = false
        }
    }

    /// Trims the head of the window if total render weight exceeds `maxBudget`
    /// and the user is at the bottom. Call between turns (after `settle()`).
    func trimIfNeeded() {
        guard isUserAtBottom else { return }
        guard totalWeight(of: messages) > maxBudget else { return }
        guard contentCount(in: messages) > minMessages else { return }

        // Walk from the end, keeping pageBudget weight (but at least minMessages)
        var accumulated = 0
        var contentKept = 0
        var trimPoint = messages.count
        for j in stride(from: messages.count - 1, through: 0, by: -1) {
            accumulated += weight(of: messages[j])
            if isContentChatMessage(messages[j]) { contentKept += 1 }
            if accumulated >= pageBudget, contentKept >= minMessages {
                trimPoint = j
                break
            }
        }

        let safeTrim = safeTrimIndex(in: messages, target: trimPoint, direction: .fromStart)
        guard safeTrim > 0 else { return }

        messages.removeFirst(safeTrim)
        windowStartIndex += safeTrim
    }

    /// Removes the trailing user message so the caller can re-send it.
    ///
    /// Returns that message and, when safe, its persisted row for the caller to
    /// delete. Returns nil if the tail isn't a non-empty user message.
    ///
    /// The persisted row is only returned when the window sits at the bottom
    /// (`!hasNewerMessages`); otherwise SwiftData is left untouched and the next
    /// send reconciles it. `allPersisted` is trimmed before `messages` so the
    /// counts stay in step — otherwise `hasNewerMessages` briefly reads true and
    /// `send` would re-add the message.
    func rewindTrailingUserMessage() -> (message: ChatMessage, persisted: Message?)? {
        guard let last = messages.last,
              last.role == "user",
              let content = last.content?.trimmingCharacters(in: .whitespaces),
              !content.isEmpty
        else { return nil }

        var persisted: Message?
        if isPreloaded, !hasNewerMessages,
           let tail = allPersisted.last, tail.role == "user"
        {
            allPersisted.removeLast()
            persisted = tail
        }
        messages.removeLast()
        return (last, persisted)
    }

    func snapToBottom() {
        guard isPreloaded else { return }
        let start = walkBackForBudget(
            in: allPersisted,
            from: allPersisted.count,
            budget: pageBudget
        )
        let safeStart = safeTrimIndexPersisted(
            in: allPersisted,
            target: start,
            direction: .fromStart
        )
        messages = Array(allPersisted[safeStart...]).map { $0.toChatMessage() }
        windowStartIndex = safeStart
    }
}
