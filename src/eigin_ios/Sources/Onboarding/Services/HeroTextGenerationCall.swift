import Foundation

/// Generates a short first-person hero paragraph for the reveal screen.
///
/// The hero text is a compact 1–2 sentence introduction the agent says about
/// itself, based on its generated core texts. It is shown to the user as a
/// "your agent is ready" moment at the end of onboarding.
struct HeroTextGenerationCall {
    let chatService: ChatService

    /// Maximum characters per core text to keep the prompt under budget.
    /// TokenEstimator estimates ~4 chars/token, so 400 chars ≈ 100 tokens.
    static let maxCoreLength = 400

    /// Generates the hero paragraph.
    ///
    /// - Parameters:
    ///   - identityCore: The agent's identity document.
    ///   - userCore: The agent's user document.
    ///   - soulCore: The agent's soul document.
    ///   - language: The user's preferred language.
    ///   - baseURL: Provider base URL.
    ///   - providerID: Provider UUID for keychain key resolution.
    ///   - model: Model identifier string.
    /// - Returns: The generated hero text, or `nil` if generation failed.
    func run(
        identityCore: String,
        userCore: String,
        soulCore: String,
        language: AppLanguage,
        baseURL: String,
        providerID: UUID,
        model: String
    ) async throws -> String? {
        let (systemPrompt, userPrompt) = buildPrompts(
            identityCore: identityCore,
            userCore: userCore,
            soulCore: soulCore,
            language: language
        )
        let messages: [ChatMessage] = [
            ChatMessage(role: "system", content: systemPrompt),
            ChatMessage(role: "user", content: userPrompt),
        ]

        let stream = try await chatService.chatCompletionStream(
            baseURL: baseURL,
            providerID: providerID,
            messages: messages,
            model: model
        )

        var output = ""
        for try await token in stream {
            output += token
        }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Private

    private func buildPrompts(
        identityCore: String,
        userCore: String,
        soulCore: String,
        language: AppLanguage
    ) -> (system: String, user: String) {
        let system = """
        You write short first-person introductions for AI agents. One or two sentences. Direct and personal.
        """

        let truncatedIdentity = String(identityCore.prefix(Self.maxCoreLength))
        let truncatedUser = String(userCore.prefix(Self.maxCoreLength))
        let truncatedSoul = String(soulCore.prefix(Self.maxCoreLength))

        let user = """
        Write a short first-person introduction this agent would say about itself.
        Do NOT mention the agent's name — the name is shown separately.

        Here is an example about a completely different agent — do not copy its topics or phrasing:

        I'm here to help you stay organized and find calm in a busy schedule. I keep track of what matters and remind you before things slip.

        Use these core texts as context (they describe the real agent):

        Identity: \(truncatedIdentity)

        User: \(truncatedUser)

        Soul: \(truncatedSoul)

        Write in \(language
            .displayName). Use your own words. Respond with the introduction text only.
        """

        return (system, user)
    }
}
