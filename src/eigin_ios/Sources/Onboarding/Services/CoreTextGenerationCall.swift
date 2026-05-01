import Foundation

/// Generates a single agent core text document from onboarding data.
///
/// Makes one model call per document type. Each call sends a light system
/// prompt plus a detailed user message with structured context, instructions,
/// and an example. Small models tend to follow user messages more reliably
/// than dense system prompts.
struct CoreTextGenerationCall {
    let chatService: ChatService

    enum DocumentType {
        case identity
        case user
    }

    /// Generates one core text document.
    ///
    /// - Parameters:
    ///   - type: Which document to generate — identity or user.
    ///   - data: Collected onboarding data including extraction reasons.
    ///   - language: The user's preferred language.
    ///   - baseURL: Provider base URL.
    ///   - providerID: Provider UUID for keychain key resolution.
    ///   - model: Model identifier string.
    /// - Returns: The generated document text, or `nil` if generation failed.
    func run(
        type: DocumentType,
        data: OnboardingData,
        language: AppLanguage,
        baseURL: String,
        providerID: UUID,
        model: String
    ) async throws -> String? {
        let (systemPrompt, userPrompt) = buildPrompts(type: type, data: data, language: language)
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
        type: DocumentType,
        data: OnboardingData,
        language: AppLanguage
    ) -> (system: String, user: String) {
        let system = """
        You write core texts for personal AI agents. Core texts are short, living documents that shape how an agent behaves and relates to its user. Be direct, personal, and specific. No filler.
        """

        let contextSection = buildContextSection(data: data)
        let example = type == .identity ? identityExample : userExample
        let instructions = type == .identity ? identityInstructions : userInstructions
        let label = type == .identity ? "identity" : "user"

        let user = """
        \(instructions)

        Here is an example of the tone and length expected. It is about a completely different user — do not copy its phrases, topics, or sentence structures:

        \(example)

        \(contextSection)

        Write this document in \(language.displayName). Use your own words.

        Now write the real \(label) document. Respond with the document text only.
        """

        return (system, user)
    }

    private func buildContextSection(data: OnboardingData) -> String {
        var section = "Here is what you know about the user, and why you know it:\n"

        if let name = data.userName {
            let reason = data.userNameReason ?? "the user told you"
            section += "- Their name is \(name). (Reason: \(reason))\n"
        }
        if let about = data.userAbout {
            let reason = data.userAboutReason ?? "the user told you"
            section += "- They are \(about). (Reason: \(reason))\n"
        }
        if let context = data.userContext {
            let reason = data.userContextReason ?? "the user told you"
            section += "- They use AI for \(context). (Reason: \(reason))\n"
        }
        if let style = data.stylePreference {
            let reason = data.stylePreferenceReason ?? "the user told you"
            section += "- They prefer \(style) communication. (Reason: \(reason))\n"
        }
        if let priority = data.priority {
            let reason = data.priorityReason ?? "the user told you"
            section += "- Their top priority is \(priority.rawValue). (Reason: \(reason))\n"
        }
        if let agentName = data.agentName {
            let reason = data.agentNameReason ?? "the user told you"
            section += "- The agent is named \(agentName) \(data.agentEmoji ?? "🤖"). (Reason: \(reason))\n"
        }

        if let correction = data.summaryCorrection, !correction.isEmpty {
            let reason = data.summaryCorrectionReason ?? "the user corrected you"
            section += "\nThe user provided this correction: \(correction) (Reason: \(reason))\n"
        }

        return section
    }

    private var identityInstructions: String {
        """
        Write the AI agent's identity document.
        Write it in first person ("I..."). This is the agent describing itself.
        Cover: what the agent is like, how it behaves, what its voice is, how it approaches helping.
        Do NOT describe the user here. Do NOT use the user's name.
        2–4 sentences. One continuous paragraph.
        """
    }

    private var userInstructions: String {
        """
        Write the user document.
        Write it in third person ("they...", "she...", "he..."). This describes the person using the agent.
        Cover: what the user is like, what they use AI for, what matters to them, what kind of support they need.
        Do NOT describe the agent here. Do NOT write as the agent.
        2–4 sentences. One continuous paragraph.
        """
    }

    private var identityExample: String {
        """
        I am calm, curious, and quietly stubborn about getting things right. I ask questions before I answer, and I never pretend to know what I don't. When the user is stuck, I help them untangle their own thinking rather than handing them conclusions.
        """
    }

    private var userExample: String {
        """
        They work in a creative field and use AI to push past blocks and organize scattered ideas. They value honesty over flattery, and they need someone who can keep up with rapid topic shifts without losing the thread. Patience and a sense of humor go a long way with them.
        """
    }
}
