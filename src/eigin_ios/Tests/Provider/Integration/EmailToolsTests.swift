@testable import Eigin
import Foundation
import SwiftData
import Testing

/// Drives the five email tools against a fake ``EmailProvider``, verifying
/// argument parsing, result envelopes, and error paths — the tools are the
/// firm agent-facing contract, so their behavior matters more than any one
/// backend.
@Suite("Email Tools")
struct EmailToolsTests {
    @MainActor
    private func makeAgent() throws -> Agent {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Schema(SchemaV1.models, version: SchemaV1.versionIdentifier),
            configurations: config
        )
        let agent = Agent(name: "TestAgent", providerID: UUID(), model: "test-model")
        container.mainContext.insert(agent)
        return agent
    }

    private func call(_ name: String, _ arguments: String) -> ToolCall {
        ToolCall(
            id: "call_\(name)",
            type: "function",
            function: .init(name: name, arguments: arguments)
        )
    }

    // MARK: - list_emails

    @Test @MainActor func listEmailsReturnsProviderResults() async throws {
        let provider = FakeEmailProvider()
        provider.summaries = [
            EmailSummary(
                id: "1", threadID: "t1", from: "a@b.com", subject: "Hi",
                snippet: "snippet", date: "2026-01-01"
            ),
        ]
        let tool = ListEmailsTool(provider: provider)
        let agent = try makeAgent()

        let result = await tool.execute(call("email_list", "{}"), agent: agent)

        #expect(!result.isError)
        #expect(result.content.contains("\"id\":\"1\""))
    }

    @Test @MainActor func listEmailsSurfacesProviderError() async throws {
        let provider = FakeEmailProvider()
        provider.errorToThrow = EmailProviderError.notAuthenticated
        let tool = ListEmailsTool(provider: provider)
        let agent = try makeAgent()

        let result = await tool.execute(call("email_list", "{}"), agent: agent)

        #expect(result.isError)
    }

    // MARK: - search_emails

    @Test @MainActor func searchEmailsRequiresQuery() async throws {
        let tool = SearchEmailsTool(provider: FakeEmailProvider())
        let agent = try makeAgent()

        let result = await tool.execute(call("email_search", "{}"), agent: agent)

        #expect(result.isError)
    }

    @Test @MainActor func searchEmailsPassesQueryToProvider() async throws {
        let provider = FakeEmailProvider()
        let tool = SearchEmailsTool(provider: provider)
        let agent = try makeAgent()

        _ = await tool.execute(
            call("email_search", #"{"query":"from:alice"}"#),
            agent: agent
        )

        #expect(provider.lastSearchQuery == "from:alice")
    }

    // MARK: - read_email

    @Test @MainActor func readEmailRequiresID() async throws {
        let tool = ReadEmailTool(provider: FakeEmailProvider())
        let agent = try makeAgent()

        let result = await tool.execute(call("email_read", "{}"), agent: agent)

        #expect(result.isError)
    }

    @Test @MainActor func readEmailReturnsFullMessage() async throws {
        let provider = FakeEmailProvider()
        let tool = ReadEmailTool(provider: provider)
        let agent = try makeAgent()

        let result = await tool.execute(
            call("email_read", #"{"id":"msg-1"}"#),
            agent: agent
        )

        #expect(!result.isError)
        #expect(provider.lastReadID == "msg-1")
        #expect(result.content.contains("Hi there"))
    }

    // MARK: - send_email

    @Test @MainActor func sendEmailRequiresRecipientSubjectAndBody() async throws {
        let tool = SendEmailTool(provider: FakeEmailProvider())
        let agent = try makeAgent()

        let result = await tool.execute(call("email_send", #"{"to":"a@b.com"}"#), agent: agent)

        #expect(result.isError)
    }

    @Test @MainActor func sendEmailParsesCommaSeparatedRecipients() async throws {
        let provider = FakeEmailProvider()
        let tool = SendEmailTool(provider: provider)
        let agent = try makeAgent()

        let result = await tool.execute(
            call(
                "email_send",
                #"{"to":"a@b.com, c@d.com","subject":"Hi","body":"Body text"}"#
            ),
            agent: agent
        )

        #expect(!result.isError)
        #expect(provider.lastSendTo == ["a@b.com", "c@d.com"])
        #expect(provider.lastSendBody == "Body text")
    }

    // MARK: - reply_email

    @Test @MainActor func replyEmailRequiresMessageIDAndBody() async throws {
        let tool = ReplyEmailTool(provider: FakeEmailProvider())
        let agent = try makeAgent()

        let result = await tool.execute(call("email_reply", "{}"), agent: agent)

        #expect(result.isError)
    }

    @Test @MainActor func replyEmailPassesMessageIDAndBodyToProvider() async throws {
        let provider = FakeEmailProvider()
        let tool = ReplyEmailTool(provider: provider)
        let agent = try makeAgent()

        let result = await tool.execute(
            call("email_reply", #"{"message_id":"msg-1","body":"Thanks!"}"#),
            agent: agent
        )

        #expect(!result.isError)
        #expect(provider.lastReplyMessageID == "msg-1")
        #expect(provider.lastReplyBody == "Thanks!")
    }
}
