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
        let system = Prompt.Onboarding.heroSystem

        let user = Prompt.Onboarding.heroUser(
            identity: String(identityCore.prefix(Self.maxCoreLength)),
            user: String(userCore.prefix(Self.maxCoreLength)),
            soul: String(soulCore.prefix(Self.maxCoreLength)),
            language: language.displayName
        )

        return (system, user)
    }
}
