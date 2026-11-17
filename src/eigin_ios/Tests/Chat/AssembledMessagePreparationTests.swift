@testable import Eigin
import Factory
import Foundation
import SwiftData
import Testing

@Suite("Assembled SDK turn preparation", .serialized)
@MainActor
struct AssembledMessagePreparationTests {
    @Test(
        arguments: [InteractionMode.text, .liveCall, .headless],
        ["apple-foundation-model", "gpt-4.1"]
    )
    func sharedTurnPathUsesSDKSelectionAndModelCapabilities(
        mode: InteractionMode,
        model: String
    ) async throws {
        let store = try ModelContainer(
            for: Schema(SchemaV15.models, version: SchemaV15.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let provider = Provider(name: "Test", baseURL: "https://fake.local")
        let agent = Agent(name: "Test", providerID: provider.id, model: model)
        agent.bootstrapComplete = true
        store.mainContext.insert(provider)
        store.mainContext.insert(agent)
        let knowledge = FakeKnowledgeService()
        Container.shared.modelContainer.register { store }
        Container.shared.knowledgeService.register { knowledge }
        Container.shared.intentService.register { PreviewIntentService() }
        defer {
            Container.shared.intentService.reset()
            Container.shared.knowledgeService.reset()
            Container.shared.modelContainer.reset()
        }
        var summary = ChatMessage(role: "system", content: "memory")
        summary.isCompactionSummary = true
        summary.compactionRetainedMessageCount = 0
        let attachment = MessageAttachment(kind: .image, mimeType: "image/png", byteCount: 123)
        let current = ChatMessage(
            role: "user",
            content: "question",
            providerMetadata: ["local": "value"],
            attachments: [attachment]
        )
        let history = [ChatMessage(role: "user", content: "old"), summary, current]
        let result = try await MessagePipeline.prepareTurn(
            messages: history, agent: agent, space: nil,
            permissionPolicy: AgentPermissionPolicy(
                builtInGrants: [:],
                discoveredGrants: [:],
                chatGrants: [],
                canPromptUser: false
            ),
            spaceID: nil, gatekeeper: Gatekeeper(
                proactivity: .reactive,
                knowledgeService: knowledge
            ),
            mode: mode, hasSpaces: false
        )
        let isSmall = model == "apple-foundation-model"
        #expect(result.isSmallContext == isSmall)
        #expect(result.apiMessages.map(\.role) == ["system", "user", "assistant", "user"])
        #expect(result.apiMessages[0]
            .content ==
            (isSmall ? SystemPrompt.buildSmall(for: agent) : SystemPrompt.build(for: agent)))
        #expect(result.apiMessages[1].localID == "context-summary")
        #expect(result.apiMessages[3].localID == current.localID)
        #expect(result.apiMessages[3].attachments == (isSmall ? nil : [attachment]))
        #expect(result.apiMessages[3].providerMetadata == current.providerMetadata)
        #expect(result.apiMessages[3].content?.contains("cannot view images") == isSmall)
        #expect(result.historyMessageIDs == history.map(\.localID))
        #expect(history[2].attachments == [attachment])
        #expect(history[2].content == "question")
    }
}

extension AssembledMessagePreparationTests {
    @Test(arguments: [0, 1])
    func normalContextHintsUseOnlySelectedHistory(retainedCount: Int) async throws {
        let store = try ModelContainer(
            for: Schema(SchemaV15.models, version: SchemaV15.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let provider = Provider(name: "Test", baseURL: "https://fake.local")
        let agent = Agent(name: "Test", providerID: provider.id, model: "gpt-4.1")
        agent.bootstrapComplete = true
        store.mainContext.insert(provider)
        store.mainContext.insert(agent)
        let knowledge = FakeKnowledgeService()
        Container.shared.modelContainer.register { store }
        Container.shared.knowledgeService.register { knowledge }
        Container.shared.intentService.register { PreviewIntentService() }
        defer {
            Container.shared.intentService.reset()
            Container.shared.knowledgeService.reset()
            Container.shared.modelContainer.reset()
            UserDefaults.standard.removeObject(forKey: "hint_history_\(agent.id.uuidString)")
            UserDefaults.standard
                .removeObject(forKey: "hint_shows_hint_history_\(agent.id.uuidString)")
        }
        var summary = ChatMessage(role: "system", content: "memory")
        summary.isCompactionSummary = true
        summary.compactionRetainedMessageCount = retainedCount
        let history = [
            ChatMessage(role: "assistant", content: "earlier exchange"),
            summary,
            ChatMessage(role: "user", content: "continue"),
        ]
        let result = try await MessagePipeline.prepareTurn(
            messages: history, agent: agent, space: nil,
            permissionPolicy: AgentPermissionPolicy(
                builtInGrants: [:],
                discoveredGrants: [:],
                chatGrants: [],
                canPromptUser: false
            ),
            spaceID: nil, gatekeeper: Gatekeeper(
                proactivity: .reactive,
                knowledgeService: knowledge
            ),
            mode: .text, hasSpaces: false
        )
        #expect(!result.isSmallContext)
        #expect(result.apiMessages[0].content == SystemPrompt.build(for: agent))
        let outgoing = try #require(result.apiMessages.last?.content)
        #expect(outgoing.contains("<system_hint>"))
        #expect(outgoing.contains("## Hint\n") == (retainedCount == 1))
    }
}
