@testable import Eigin
import Foundation
import Testing

@MainActor
struct SkillConnectionGateTests {
    @Test func changedCapabilitiesRequireAnotherReply() {
        let gate = SkillConnectionGate()
        let chat = UUID()
        gate.beginUserTurn(chatID: chat, messageID: "first")
        #expect(isAsk(gate.request(
            chatID: chat,
            skillID: "planning",
            missing: [.calendar],
            messageID: "first"
        )))
        gate.beginUserTurn(chatID: chat, messageID: "second")
        #expect(isAsk(gate.request(
            chatID: chat,
            skillID: "planning",
            missing: [.calendar, .reminders],
            messageID: "second"
        )))
        #expect(isWait(gate.request(
            chatID: chat,
            skillID: "planning",
            missing: [.calendar, .reminders],
            messageID: "second"
        )))
    }

    @Test func anotherSkillCannotReuseAPendingRequest() {
        let gate = SkillConnectionGate()
        let chat = UUID()
        gate.beginUserTurn(chatID: chat, messageID: "first")
        _ = gate.request(
            chatID: chat,
            skillID: "calendar",
            missing: [.calendar],
            messageID: "first"
        )
        gate.beginUserTurn(chatID: chat, messageID: "second")
        #expect(isAsk(gate.request(
            chatID: chat,
            skillID: "planning",
            missing: [.calendar],
            messageID: "second"
        )))
    }

    @Test func reservationBlocksConcurrentRequestsAndStaleCompletion() {
        let gate = SkillConnectionGate()
        let chat = UUID()
        gate.beginUserTurn(chatID: chat, messageID: "first")
        _ = gate.request(chatID: chat, skillID: "health", missing: [.health], messageID: "first")
        gate.beginUserTurn(chatID: chat, messageID: "second")
        guard case .connect(let attempt) = gate.request(
            chatID: chat,
            skillID: "health",
            missing: [.health],
            messageID: "second"
        ) else {
            Issue.record("A later reply must allow one connection attempt")
            return
        }
        #expect(isWait(gate.request(
            chatID: chat,
            skillID: "health",
            missing: [.health],
            messageID: "second"
        )))
        gate.beginUserTurn(chatID: chat, messageID: "third")
        #expect(isWait(gate.request(
            chatID: chat,
            skillID: "health",
            missing: [.health],
            messageID: "third"
        )))
        gate.finish(chatID: chat, skillID: "health", attempt: attempt)
        #expect(isAsk(gate.request(
            chatID: chat,
            skillID: "health",
            missing: [.health],
            messageID: "third"
        )))
        gate.finish(chatID: chat, skillID: "health", attempt: attempt)
        gate.beginUserTurn(chatID: chat, messageID: "fourth")
        guard case .connect = gate.request(
            chatID: chat,
            skillID: "health",
            missing: [.health],
            messageID: "fourth"
        ) else {
            Issue.record("A stale completion must not alter the fresh handshake")
            return
        }
    }

    @Test func reusingTheSameUserMessageDoesNotReleaseTheGate() {
        let gate = SkillConnectionGate()
        let chat = UUID()
        gate.beginUserTurn(chatID: chat, messageID: "first")
        _ = gate.request(chatID: chat, skillID: "health", missing: [.health], messageID: "first")
        gate.beginUserTurn(chatID: chat, messageID: "first")
        #expect(isWait(gate.request(
            chatID: chat,
            skillID: "health",
            missing: [.health],
            messageID: "first"
        )))
    }

    private func isAsk(_ decision: SkillConnectionGate.Decision) -> Bool {
        if case .askUser = decision { return true }
        return false
    }

    private func isWait(_ decision: SkillConnectionGate.Decision) -> Bool {
        if case .waitForUser = decision { return true }
        return false
    }
}
