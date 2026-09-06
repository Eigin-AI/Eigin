import SwiftData

/// Seeded state shared by all screenshot scenes: one agent with its space, and
/// the three connection kinds (Eigin relay, own-key provider, local model).
/// Chat scenes compose their turn as literal `ChatItem`s (see
/// ``ScreenshotCanvas``); the store here backs the header and Connections.
struct ScreenshotFixtures {
    let agent: Agent
    let space: Space

    static func seed(into context: ModelContext) -> ScreenshotFixtures {
        let relayProvider = Provider(name: "Eigin", baseURL: "eigin-relay://")
        relayProvider.availableModels = ["gpt-5.6", "claude-sonnet-5"]
        relayProvider.enabledModels = ["gpt-5.6"]
        context.insert(relayProvider)

        let ownKeyProvider = Provider(name: "Work server", baseURL: "https://work.internal/v1")
        ownKeyProvider.availableModels = ["gpt-5.5", "claude-haiku-4-5"]
        ownKeyProvider.enabledModels = ["gpt-5.5"]
        context.insert(ownKeyProvider)

        // The local provider record the app itself creates once the on-device
        // model is ready (see ContentView.ensureLocalProvider).
        let localProvider = Provider(name: Localized.Provider.onDevice, baseURL: "local://")
        localProvider.availableModels = ["gemma-4-e2b"]
        localProvider.enabledModels = ["gemma-4-e2b"]
        context.insert(localProvider)

        let agent = Agent(name: "Eigin", providerID: relayProvider.id, model: "gpt-5.6")
        agent.emoji = "🧠"
        agent.identityCore = "I am Eigin, a personal assistant."
        agent.userCore = "The user lives in Copenhagen and runs their household from their phone."
        agent.soulCore = ""
        agent.bootstrapComplete = true
        context.insert(agent)

        let space = Space(agentID: agent.id)
        space.name = "Home"
        space.emoji = "🏡"
        space.bootstrapComplete = true
        context.insert(space)

        return ScreenshotFixtures(agent: agent, space: space)
    }

    /// The chat backing the canvas header. `titleOrigin` is `.edited` so the
    /// title generator never replaces the copy.
    @discardableResult
    static func chat(
        _ context: ModelContext,
        agent: Agent,
        spaceID: UUID? = nil,
        title: String
    ) -> Chat {
        let chat = Chat(agentID: agent.id, title: title)
        chat.titleOriginRaw = .edited
        chat.spaceID = spaceID
        chat.createdAt = .now
        chat.updatedAt = .now
        context.insert(chat)
        return chat
    }

    /// A helper tool call with the given name and JSON arguments.
    static func toolCall(_ id: String, name: String, arguments: String) -> ToolCall {
        ToolCall(
            id: id,
            type: "function",
            function: .init(name: name, arguments: arguments)
        )
    }

    /// The next occurrence of `weekday` (1 = Sunday) at the given time, so
    /// scene dates always read as "this coming Thursday".
    static func nextWeekday(_ weekday: Int, at hour: Int, _ minute: Int = 0) -> Date {
        let calendar = Calendar.current
        var date = Date.now
        repeat {
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        } while calendar.component(.weekday, from: date) != weekday
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
    }
}
