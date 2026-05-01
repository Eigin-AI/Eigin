@testable import Eigin
import Testing

@MainActor
@Suite("MessageWindow")
struct MessageWindowTests {
    // MARK: - Helpers

    private func userMsg(
        _ id: String = UUID().uuidString,
        content: String = "hello"
    ) -> ChatMessage {
        ChatMessage(role: "user", content: content, localID: id)
    }

    private func assistantMsg(
        _ id: String = UUID().uuidString,
        content: String = "hi"
    ) -> ChatMessage {
        ChatMessage(role: "assistant", content: content, localID: id)
    }

    private func toolCallAssistant(
        _ id: String = UUID().uuidString,
        callID: String = "tc1"
    ) -> ChatMessage {
        ChatMessage(
            role: "assistant",
            content: nil,
            toolCalls: [ToolCall(
                id: callID,
                type: "function",
                function: .init(name: "test", arguments: "{}")
            )],
            localID: id
        )
    }

    private func toolResult(
        _ callID: String = "tc1",
        id: String = UUID().uuidString
    ) -> ChatMessage {
        ChatMessage(role: "tool", content: "result", toolCallID: callID, localID: id)
    }

    /// Build a conversation of N user/assistant pairs (2N content messages).
    /// Each message is short (~5 chars), so weight ≈ 1 per content message.
    private func conversation(turns: Int) -> [ChatMessage] {
        var msgs: [ChatMessage] = []
        for i in 0 ..< turns {
            msgs.append(userMsg("u\(i)"))
            msgs.append(assistantMsg("a\(i)"))
        }
        return msgs
    }

    /// Build a heavy message with code blocks and long content.
    private func heavyAssistantMsg(_ id: String = UUID().uuidString) -> ChatMessage {
        let code = "```\nlet x = 1\n```"
        let body = String(repeating: "a", count: 2100)
        return assistantMsg(id, content: body + "\n" + code)
    }

    // MARK: - Weight function

    @Test("Weight of short message is 1")
    func weightShortMessage() {
        let window = MessageWindow()
        let msg = userMsg(content: "Thanks!")
        #expect(window.weight(of: msg) == 1)
    }

    @Test("Weight of empty/tool messages is 0")
    func weightNonContent() {
        let window = MessageWindow()
        #expect(window.weight(of: toolCallAssistant()) == 0)
        #expect(window.weight(of: toolResult()) == 0)
    }

    @Test("Weight accounts for text length")
    func weightTextLength() {
        let window = MessageWindow()
        // 800 chars → 1 base + 4 (800/200) = 5
        let msg = userMsg(content: String(repeating: "x", count: 800))
        #expect(window.weight(of: msg) == 5)
    }

    @Test("Weight accounts for code blocks")
    func weightCodeBlocks() {
        let window = MessageWindow()
        // Short text with one fenced code block (``` open + ``` close = 2 occurrences × 2 = +4)
        let msg = assistantMsg(content: "Here:\n```\ncode\n```")
        let w = window.weight(of: msg)
        // 1 base + 0 (< 200 chars) + 4 (two ``` markers) = 5
        #expect(w == 5)
    }

    @Test("Weight accounts for math blocks")
    func weightMathBlocks() {
        let window = MessageWindow()
        let msg = assistantMsg(content: "Formula: $$E=mc^2$$")
        let w = window.weight(of: msg)
        // 1 base + 0 (< 200 chars) + 4 (two $$ markers) = 5
        #expect(w == 5)
    }

    @Test("Weight large content bonus")
    func weightLargeContent() {
        let window = MessageWindow()
        let msg = assistantMsg(content: String(repeating: "a", count: 2100))
        let w = window.weight(of: msg)
        // 1 base + 10 (2100/200) + 3 (>2000 bonus) = 14
        #expect(w == 14)
    }

    @Test("Weight of heavy message with code blocks and long text")
    func weightHeavyMessage() {
        let window = MessageWindow()
        let msg = heavyAssistantMsg()
        let w = window.weight(of: msg)
        // Long text (~2100 + code block): base 1 + chars/200 + code block markers + large bonus
        #expect(w > 10)
    }

    // MARK: - trimIfNeeded

    @Test("Does not trim when under maxBudget")
    func noTrimUnderThreshold() {
        let window = MessageWindow(pageBudget: 30, maxBudget: 60, minMessages: 5)
        window.messages = conversation(turns: 10) // 20 content messages, weight ~20
        window.isUserAtBottom = true

        window.trimIfNeeded()

        #expect(window.messages.count == 20)
        #expect(window.windowStartIndex == 0)
    }

    @Test("Trims when total weight exceeds maxBudget")
    func trimsWhenOverBudget() {
        // Use small budgets so short messages trigger trim
        let window = MessageWindow(pageBudget: 3, maxBudget: 6, minMessages: 2)
        window.messages = conversation(turns: 6) // 12 content messages, weight ~12
        window.isUserAtBottom = true

        window.trimIfNeeded()

        let remaining = window.totalWeight(of: window.messages)
        #expect(remaining <= window.maxBudget)
        #expect(window.windowStartIndex > 0)
    }

    @Test("Does not trim when user is scrolled up")
    func noTrimWhenScrolledUp() {
        let window = MessageWindow(pageBudget: 3, maxBudget: 6, minMessages: 2)
        window.messages = conversation(turns: 6) // 12 content messages, weight ~12
        window.isUserAtBottom = false

        window.trimIfNeeded()

        #expect(window.messages.count == 12)
        #expect(window.windowStartIndex == 0)
    }

    @Test("windowStartIndex advances by the number of trimmed messages")
    func windowStartIndexAdvances() {
        let window = MessageWindow(pageBudget: 3, maxBudget: 6, minMessages: 2)
        window.windowStartIndex = 3
        window.messages = conversation(turns: 6) // 12 content messages
        window.isUserAtBottom = true

        let beforeCount = window.messages.count
        window.trimIfNeeded()

        let trimmed = beforeCount - window.messages.count
        #expect(window.windowStartIndex == 3 + trimmed)
    }

    @Test("Does not split a tool group when trimming")
    func preservesToolGroups() {
        let window = MessageWindow(pageBudget: 3, maxBudget: 5, minMessages: 2)
        // 5 content messages with a tool group near the trim boundary
        window.messages = [
            userMsg("u0"),
            assistantMsg("a0"),
            userMsg("u1"),
            toolCallAssistant("tc-ast", callID: "call1"),
            toolResult("call1", id: "tr1"),
            assistantMsg("a1"), // content 3
            userMsg("u2"), // content 4
            assistantMsg("a2"), // content 5
        ]
        window.isUserAtBottom = true

        window.trimIfNeeded()

        // The tool group (tc-ast + tr1) should not be split — either fully kept or fully trimmed
        let hasToolCallAssistant = window.messages.contains { $0.localID == "tc-ast" }
        let hasToolResult = window.messages.contains { $0.localID == "tr1" }
        #expect(hasToolCallAssistant == hasToolResult, "Tool group must not be split")
    }

    @Test("Trim is idempotent — second call is a no-op")
    func trimIdempotent() {
        let window = MessageWindow(pageBudget: 3, maxBudget: 6, minMessages: 2)
        window.messages = conversation(turns: 8) // 16 content messages
        window.isUserAtBottom = true

        window.trimIfNeeded()
        let countAfterFirst = window.messages.count
        let startAfterFirst = window.windowStartIndex

        window.trimIfNeeded()
        #expect(window.messages.count == countAfterFirst)
        #expect(window.windowStartIndex == startAfterFirst)
    }

    @Test("Exactly at maxBudget does not trigger trim")
    func exactlyAtMaxNoTrim() {
        // 6 short messages, weight 1 each = total 6, maxBudget 6
        let window = MessageWindow(pageBudget: 3, maxBudget: 6, minMessages: 2)
        window.messages = conversation(turns: 3) // 6 content messages, weight ~6
        window.isUserAtBottom = true

        window.trimIfNeeded()

        #expect(window.messages.count == 6)
        #expect(window.windowStartIndex == 0)
    }

    @Test("Deferred trim fires on next call when user returns to bottom")
    func deferredTrimFires() {
        let window = MessageWindow(pageBudget: 3, maxBudget: 6, minMessages: 2)
        window.messages = conversation(turns: 8) // 16 content messages
        window.isUserAtBottom = false

        window.trimIfNeeded()
        #expect(window.messages.count == 16) // no trim

        window.isUserAtBottom = true
        window.trimIfNeeded()

        let remaining = window.totalWeight(of: window.messages)
        #expect(remaining <= window.maxBudget)
    }

    @Test("Tail messages are preserved — trim removes from the head")
    func tailPreserved() throws {
        let window = MessageWindow(pageBudget: 3, maxBudget: 6, minMessages: 2)
        window.messages = conversation(turns: 6) // 12 content messages
        window.isUserAtBottom = true

        let lastID = try #require(window.messages.last?.localID)
        window.trimIfNeeded()

        #expect(window.messages.last?.localID == lastID)
    }

    // MARK: - minMessages floor

    @Test("Does not trim below minMessages even with heavy content")
    func minMessagesFloor() {
        let window = MessageWindow(pageBudget: 5, maxBudget: 10, minMessages: 5)
        // 3 heavy messages — fewer than minMessages, should not trim
        window.messages = [
            userMsg("u0"),
            heavyAssistantMsg("a0"),
            userMsg("u1"),
        ]
        window.isUserAtBottom = true

        window.trimIfNeeded()

        #expect(window.messages.count == 3)
        #expect(window.windowStartIndex == 0)
    }

    // MARK: - Light conversation stays large

    @Test("Light conversation fits many messages under default budget")
    func lightConversationFits() {
        let window = MessageWindow() // default: pageBudget=30, maxBudget=60
        window.messages = conversation(turns: 20) // 40 short messages, weight ~40
        window.isUserAtBottom = true

        window.trimIfNeeded()

        // Total weight ~40 < maxBudget 60, should not trim
        #expect(window.messages.count == 40)
    }

    // MARK: - Heavy conversation gets trimmed

    @Test("Heavy conversation trims but keeps at least minMessages")
    func heavyConversationTrims() {
        let window = MessageWindow(pageBudget: 15, maxBudget: 30, minMessages: 5)
        // Build heavy conversation
        var msgs: [ChatMessage] = []
        for i in 0 ..< 15 {
            msgs.append(userMsg("u\(i)"))
            msgs.append(heavyAssistantMsg("a\(i)"))
        }
        window.messages = msgs // 30 content messages, very heavy
        window.isUserAtBottom = true

        window.trimIfNeeded()

        let cc = window.messages.count(where: {
            $0.role != "tool" && $0.content != nil && !$0.content!.isEmpty
        })
        #expect(cc >= window.minMessages)
        #expect(window.totalWeight(of: window.messages) <= window
            .maxBudget + 30) // trimmed significantly
        #expect(window.windowStartIndex > 0)
    }

    // MARK: - No eager trim

    @Test("No trim when weight is under maxBudget even if close")
    func noEagerTrim() {
        // maxBudget = 12, put in messages with total weight ~10
        let window = MessageWindow(pageBudget: 6, maxBudget: 12, minMessages: 2)
        window.messages = conversation(turns: 5) // 10 content messages, weight ~10
        window.isUserAtBottom = true

        window.trimIfNeeded()

        #expect(window.messages.count == 10)
        #expect(window.windowStartIndex == 0)
    }
}
