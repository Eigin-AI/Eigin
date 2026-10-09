@testable import Eigin
import Foundation
import SwiftData
import Testing

@Suite("SetProactivityTool", .serialized)
struct SetProactivityToolTests {
    private let fakeScheduler = FakeBackgroundTaskScheduler()
    private let containerBox = ContainerBox()
    private let stubAuthorizer = StubNotificationAuthorizer()

    init() {
        BackgroundPromptScheduler.scheduler = fakeScheduler
        ProactivityDecision.defaults = UserDefaults(suiteName: "SetProactivityToolTests")
            ?? .standard
        ProactivityDecision.removeDecision()
    }

    /// Never touches the system notification prompt.
    private struct StubNotificationAuthorizer: NotificationAuthorizing {
        func requestIfNeeded() async -> Bool {
            true
        }
    }

    // MARK: - Helpers

    /// Holds the in-memory container alive for the test's duration — a
    /// deallocated container destroys its contexts, and the agent with them.
    @MainActor
    final class ContainerBox {
        private(set) var container: ModelContainer?

        func makeAgent() throws -> Agent {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            let container = try ModelContainer(
                for: Schema(SchemaV10.models, version: SchemaV10.versionIdentifier),
                configurations: config
            )
            self.container = container
            let agent = Agent(name: "TestAgent", providerID: UUID(), model: "test-model")
            container.mainContext.insert(agent)
            return agent
        }
    }

    private func makeCall(level: String) -> ToolCall {
        ToolCall(
            id: "call_set_proactivity",
            type: "function",
            function: .init(name: "set_proactivity", arguments: #"{"level": "\#(level)"}"#)
        )
    }

    // MARK: - Decision recording

    /// Any explicit choice — enabling or staying reactive — settles the
    /// question, so the agent stops offering proactivity in chat.
    @MainActor
    @Test(arguments: ["reactive", "balanced", "proactive"])
    func executeMarksDecision(level: String) async throws {
        let agent = try containerBox.makeAgent()

        #expect(!ProactivityDecision.isDecided())

        let tool = SetProactivityTool(notificationAuthorizer: stubAuthorizer)
        let result = await tool.execute(makeCall(level: level), agent: agent)

        #expect(result.isError == false)
        #expect(ProactivityDecision.isDecided())
    }

    /// The decline path exists for users who answer "no" to the chat offer:
    /// reactive is a valid explicit choice, not just the untouched default.
    @MainActor
    @Test func executeReactiveIsAnExplicitDecision() async throws {
        let agent = try containerBox.makeAgent()

        let tool = SetProactivityTool(notificationAuthorizer: stubAuthorizer)
        let result = await tool.execute(makeCall(level: "reactive"), agent: agent)

        #expect(result.isError == false)
        #expect(agent.proactivity == .reactive)
        #expect(ProactivityDecision.isDecided())
    }
}
