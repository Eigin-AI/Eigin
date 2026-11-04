@testable import Eigin
import Foundation
import SwiftData
import Testing

/// Drives the email tools against a fake ``EmailProvider``, verifying
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

    @Test @MainActor func foldersAreDiscoveredAndForwarded() async throws {
        let provider = FakeEmailProvider()
        provider.folders = [EmailFolder(id: "folder-1", name: "Receipts", parentID: nil)]
        let agent = try makeAgent()
        let folders = await ListEmailFoldersTool(provider: provider).execute(
            call("email_list_folders", "{}"),
            agent: agent
        )
        #expect(!folders.isError)
        #expect(folders.content.contains("Receipts"))
        let list = await ListEmailsTool(provider: provider).execute(
            call("email_list", #"{"folder_id":"folder-1","page_token":"next"}"#),
            agent: agent
        )
        #expect(!list.isError)
        #expect(provider.lastFolderID == "folder-1")
        #expect(provider.lastPageToken == "next")
        let search = await SearchEmailsTool(provider: provider).execute(
            call("email_search", #"{"folder_id":"folder-1","query":"invoice"}"#),
            agent: agent
        )
        #expect(!search.isError)
        #expect(provider.lastFolderID == "folder-1")
        #expect(provider.lastSearchQuery == "invoice")
    }

    @Test @MainActor func unsupportedFolderAccessReturnsAnError() async throws {
        let provider = IMAPEmailProvider(
            integrationID: UUID(),
            credentialStore: FakeIMAPCredentialStore()
        )
        #expect(EmailToolKit.tools(provider: provider).contains { $0.name == "email_list_folders" })
        let agent = try makeAgent()
        let folders = await ListEmailFoldersTool(provider: provider).execute(
            call("email_list_folders", "{}"),
            agent: agent
        )
        #expect(folders.isError)
        let result = await ListEmailsTool(provider: provider).execute(
            call("email_list", #"{"folder_id":"sent"}"#),
            agent: agent
        )
        #expect(result.isError)
    }

    @Test func searchSchemaUsesConnectedProviderGuidance() {
        let provider = FakeEmailProvider()
        provider.searchQueryDescription = "Use this account's query syntax."
        let schema = SearchEmailsTool(provider: provider).definition().function.parameters
        #expect(schema.properties?["query"]?.description == provider.searchQueryDescription)
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
        // The egress body is the composed text, plus at most the invisible
        // egress watermark (present when the build config enables it).
        #expect(provider.lastSendBody == Watermark.mark("Body text"))
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
        // Same contract as send: composed body plus the egress watermark.
        #expect(provider.lastReplyBody == Watermark.mark("Thanks!"))
    }
}
