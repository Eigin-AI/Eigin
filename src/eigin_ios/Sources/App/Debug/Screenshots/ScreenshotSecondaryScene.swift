import Factory
import SwiftData
import SwiftUI

/// Real secondary screens backed only by the screenshot mode's in-memory fixtures.
struct ScreenshotSecondaryScene: View {
    let scene: ScreenshotScene
    @Query private var agents: [Agent]
    @Query private var providers: [Provider]
    @Query private var spaces: [Space]
    @Query private var intents: [Intent]
    @State private var selectedModel = "claude-opus-4-6"
    @State private var isAuto = true

    var body: some View {
        NavigationStack {
            if let agent = agents.first {
                switch scene {
                case .modelPicker:
                    if let provider = providers.first(where: { $0.id == agent.providerID }) {
                        ModelPicker(
                            provider: provider,
                            selectedModel: $selectedModel,
                            isAuto: $isAuto
                        )
                    }
                case .intents: IntentsList(agentID: agent.id)
                case .intentDetail:
                    if let intent = intents
                        .first(where: { !$0.tasks.isEmpty }) { IntentDetail(intent: intent) }
                case .skills: SkillsList()
                case .skillDetail: SkillDetail(skill: BundledSkill.email)
                case .spaces: SpaceListView()
                case .spaceDetail:
                    if let space = spaces
                        .first(where: { $0.name == "Travel" }) { SpaceDetailView(space: space) }
                case .permissions: ToolPermissions(agent: agent)
                case .knowledge: KnowledgeContainer(agentID: agent.id)
                default: EmptyView()
                }
            }
        }
    }

    /// Fixtures live only in the screenshot store and never execute tools.
    static func seed(_ context: ModelContext, fixtures: ScreenshotFixtures) {
        let knowledge = FakeKnowledgeService()
        let neighbors = (1 ... 10).map { FirmEntity(
            id: "note.fixture_\($0)",
            entityType: "note",
            fields: [FirmField(name: "name", value: .string(value: "Saved thought \($0)"))]
        ) }
        let user = FirmEntity(
            id: "actor.user",
            entityType: "actor",
            fields: [FirmField(name: "name", value: .string(value: "You"))]
        )
        knowledge
            .entities = Dictionary(uniqueKeysWithValues: ([user] + neighbors).map { ($0.id, $0) })
        knowledge.relatedOutgoing[user.id] = neighbors
        Container.shared.knowledgeService.register { knowledge }
        let models = [
            "claude-opus-4-6",
            "claude-sonnet-4-6",
            "claude-haiku-4-5",
            "vendor/custom-chat",
        ]
        if let provider = try? context.fetch(FetchDescriptor<Provider>())
            .first(where: { $0.id == fixtures.agent.providerID })
        {
            provider.availableModels = models
            provider.enabledModels = models
        }
        Container.shared.providerModelRefresher
            .register { FakeProviderModelRefresher(modelsToReturn: models) }
        Container.shared.modelMetadataService.register { CatalogModelMetadataService() }
        context.insert(Integration(
            typeID: "google",
            accountLabel: "alex@example.com",
            grantedCapabilities: ["email"]
        ))
        let server = MCPServer(name: "Home Assistant", url: "https://example.invalid/mcp")
        server.cachedToolNames = ["get_state", "call_service"]
        context.insert(server)

        fixtures.space.name = "Everyday"
        fixtures.space.emoji = "🌿"
        for (name, emoji, count, privateSpace) in [
            ("Travel", "🚆", 4, false),
            ("Journal", "✍️", 8, true),
        ] {
            let space = Space(agentID: fixtures.agent.id)
            space.name = name
            space.emoji = emoji
            space.isPrivate = privateSpace
            space.bootstrapComplete = true
            space.instructions = "Prefer trains over flights when practical. Look for small hotels and vegetarian places to eat."
            context.insert(space)
            for index in 0 ..< count {
                ScreenshotFixtures.chat(
                    context,
                    agent: fixtures.agent,
                    spaceID: space.id,
                    title: "Conversation \(index + 1)"
                )
            }
        }
        for index in 0 ..< 12 {
            ScreenshotFixtures.chat(
                context,
                agent: fixtures.agent,
                spaceID: fixtures.space.id,
                title: "Conversation \(index + 1)"
            )
        }
        context.insert(Intent(
            agentID: fixtures.agent.id,
            content: "Plan a weekend in Oslo. Prefer the train, a small hotel and vegetarian places to eat.",
            tasks: [
                .init(content: "Compare train routes", completed: true),
                .init(
                    content: "Shortlist places to stay",
                    due: ScreenshotFixtures.nextWeekday(6, at: 9)
                ),
            ],
            events: [.init(
                content: "Weekend in Oslo",
                at: ScreenshotFixtures.nextWeekday(6, at: 9)
            )],
            schedules: [.init(
                content: "Check travel plans",
                frequency: .weekly,
                weekdays: [2],
                hour: 9
            )]
        ))
        context.insert(Intent(agentID: fixtures.agent.id, content: "Make more time for cooking."))
        context.insert(Intent(
            agentID: fixtures.agent.id,
            content: "Get the garden ready for spring.",
            tasks: [.init(content: "Choose seeds")]
        ))
    }
}

extension ScreenshotScene {
    var isSecondary: Bool {
        switch self {
        case .modelPicker, .intents, .intentDetail, .skills, .skillDetail, .spaces, .spaceDetail,
             .permissions, .knowledge: true
        default: false
        }
    }
}
