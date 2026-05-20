import Foundation

/// Stage definitions and greeting for the local onboarding flow.
///
/// Produces the stages passed to ``OnboardingOrchestrator``. Each stage collects
/// one piece of information. Directives are written to be natural with small local
/// models — brief, specific, and contextual.
enum LocalOnboardingScript {
    static var greeting: String {
        Localized.Onboarding.Chat.initialGreeting
    }

    static func stages(language: AppLanguage) -> [OnboardingStage] {
        [
            nameStage,
            aboutStage,
            contextStage,
            styleStage,
            priorityStage,
            agentNameStage(language: language),
            summaryStage,
        ]
    }

    // MARK: - Stages

    /// Collects the user's name or preferred handle.
    private static let nameStage = OnboardingStage(
        id: "name",
        extractor: OnboardingExtractor(
            tag: "name",
            description: "the user's name or nickname",
            examples: [
                FewShotExample(
                    userMessage: "Hey there. Um, my name is Daniel.",
                    assistantResponse: "<name reason=\"The user explicitly states their name is Daniel\">Daniel</name>"
                ),
                FewShotExample(
                    userMessage: "[Assistant: \"What should I call you?\"] \"Just Dan\"",
                    assistantResponse: "<name reason=\"The user asked to be called Dan\">Dan</name>"
                ),
                FewShotExample(
                    userMessage: "[Assistant: \"Can I just call you friend?\"] \"Yeah that's fine\"",
                    assistantResponse: "<name reason=\"The user accepted the assistant's suggestion\">friend</name>"
                ),
                FewShotExample(
                    userMessage: "I'm Bob, but you can call me Alice",
                    assistantResponse: "<name reason=\"The user prefers to be called Alice\">Alice</name>"
                ),
                FewShotExample(
                    userMessage: "why do you want to know?",
                    assistantResponse: "NONE"
                ),
            ]
        ),
        systemHint: { _, retryCount in
            if retryCount >= 2 {
                return "Briefly acknowledge, then ask directly: What should I call you? Even a nickname works."
            }
            if retryCount == 1 {
                return "Respond naturally, then ask again what they'd like to be called. A nickname or first name is fine."
            }
            return nil
        },
        store: { value, reason, data, _ in
            guard !value.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            data.userName = value
            data.userNameReason = reason
        },
        isComplete: { $0.userName != nil }
    )

    /// Collects a brief sense of who the user is — work, life, interests.
    private static let aboutStage = OnboardingStage(
        id: "about",
        extractor: OnboardingExtractor(
            tag: "about",
            description: "a brief description of who the user is, what they do, and what matters to them",
            examples: [
                FewShotExample(
                    userMessage: "I'm a product designer at a startup. I have two kids and not much free time.",
                    assistantResponse: "<about reason=\"The user describes their job and family situation\">product designer at a startup, parent of two kids</about>"
                ),
                FewShotExample(
                    userMessage: "I run my own consulting business. Travel a lot, work with tech companies.",
                    assistantResponse: "<about reason=\"The user describes their consulting business and travel\">runs own consulting business, works with tech companies, travels frequently</about>"
                ),
                FewShotExample(
                    userMessage: "I'm a student studying computer science. I like building side projects.",
                    assistantResponse: "<about reason=\"The user is a CS student who likes side projects\">CS student, enjoys building side projects</about>"
                ),
                FewShotExample(
                    userMessage: "Retired teacher. I garden and write now.",
                    assistantResponse: "<about reason=\"The user is retired, gardens and writes\">retired teacher, gardens and writes</about>"
                ),
                FewShotExample(
                    userMessage: "Not much to tell really",
                    assistantResponse: "NONE"
                ),
            ]
        ),
        systemHint: { data, retryCount in
            if retryCount >= 2 {
                return "Briefly acknowledge, then ask directly: What do you do? Even a one-sentence answer helps."
            }
            if retryCount == 1 {
                return "Respond naturally, then ask again what they do or what their life is like. A short answer is fine."
            }
            if let name = data.userName {
                return "Respond naturally. Mention their name (\(name)) and ask what they do or what their life is like — work, family, hobbies, anything that gives a sense of who they are."
            }
            return "Respond naturally, then ask what they do or what their life is like — work, family, hobbies, anything that gives a sense of who they are."
        },
        recoveryOpener: { _ in
            Localized.Onboarding.Chat.aboutYouPrompt
        },
        store: { value, reason, data, _ in
            guard !value.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            data.userAbout = value
            data.userAboutReason = reason
        },
        isComplete: { $0.userAbout != nil }
    )

    /// Collects what the user uses AI for.
    private static let contextStage = OnboardingStage(
        id: "context",
        extractor: OnboardingExtractor(
            tag: "context",
            description: "the main things the user uses AI for",
            examples: [
                FewShotExample(
                    userMessage: "I like to use AI for thinking, structuring my thoughts, and technical sparring.",
                    assistantResponse: "<context reason=\"The user lists thinking, structuring thoughts, and technical sparring\">thinking, structuring thoughts, and technical sparring</context>"
                ),
                FewShotExample(
                    userMessage: "mostly coding and writing emails",
                    assistantResponse: "<context reason=\"The user mentions coding and writing emails\">coding and writing emails</context>"
                ),
                FewShotExample(
                    userMessage: "not sure yet",
                    assistantResponse: "<context reason=\"The user doesn't have a specific use case yet\">exploring</context>"
                ),
            ]
        ),
        systemHint: { data, retryCount in
            if retryCount >= 2 {
                return "Briefly acknowledge, then ask directly: What do you mainly use AI for? Even a one-word answer helps."
            }
            if retryCount == 1 {
                return "Respond naturally, then ask again what they mainly use AI for. Even a general area like work or hobbies is fine."
            }
            if let name = data.userName {
                return "Respond naturally, then ask \(name) what they're hoping to use their personal AI for."
            }
            return "Respond naturally, then ask what they're hoping to use their personal AI for."
        },
        recoveryOpener: { _ in
            Localized.Onboarding.Chat.useCasePrompt
        },
        store: { value, reason, data, _ in
            guard !value.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            data.userContext = value
            data.userContextReason = reason
        },
        isComplete: { $0.userContext != nil }
    )

    /// Collects the user's preferred interaction style.
    private static let styleStage = OnboardingStage(
        id: "style",
        extractor: OnboardingExtractor(
            tag: "style",
            description: "the user's preferred communication style",
            examples: [
                FewShotExample(
                    userMessage: "I like it when you get straight to the point.",
                    assistantResponse: "<style reason=\"The user prefers directness\">concise and direct</style>"
                ),
                FewShotExample(
                    userMessage: "[Assistant: \"Would you prefer brief or detailed?\"] \"Brief please\"",
                    assistantResponse: "<style reason=\"The user chose brief from assistant's options\">brief</style>"
                ),
                FewShotExample(
                    userMessage: "[Assistant: \"So you'd prefer concise and direct?\"] \"Yeah exactly\"",
                    assistantResponse: "<style reason=\"The user confirmed concise and direct\">concise and direct</style>"
                ),
                FewShotExample(
                    userMessage: "Can we act like sparring partners?",
                    assistantResponse: "<style reason=\"The user asked for sparring\">sparring partner</style>"
                ),
                FewShotExample(
                    userMessage: "Talk like a pirate",
                    assistantResponse: "<style reason=\"The user requested a specific persona\">pirate</style>"
                ),
                FewShotExample(
                    userMessage: "I'd want your to be warm and encouraging.",
                    assistantResponse: "<style reason=\"The user asked for warmth and encouragement\">warm and encouraging</style>"
                ),
                FewShotExample(
                    userMessage: "I like deep, thorough discussions.",
                    assistantResponse: "<style reason=\"The user values depth and thoroughness\">deep and thorough</style>"
                ),
                FewShotExample(
                    userMessage: "Keep it playful and fun.",
                    assistantResponse: "<style reason=\"The user asked for playfulness\">playful and fun</style>"
                ),
                FewShotExample(
                    userMessage: "I don't know",
                    assistantResponse: "NONE"
                ),
            ]
        ),
        systemHint: { data, retryCount in
            if retryCount >= 2 {
                return "Briefly acknowledge, then ask directly: How do they want you to talk? Formal or casual? Brief or thorough? Playful or serious? They can pick from the options or describe their own style."
            }
            if retryCount == 1 {
                return "Respond naturally, then follow up on how they'd like you to talk. Formal or casual? Brief or thorough? Playful or serious? hey can pick from the options or describe their own style."
            }
            if let name = data.userName {
                return "Respond naturally, then ask \(name) how they'd like you to talk. Formal or casual? Brief or thorough? Playful or serious? They can pick one, mix them, or describe something entirely their own."
            }
            return "Respond naturally, then ask how they'd like you to talk. Formal or casual? Brief or thorough? Playful or serious? They can pick one, mix them, or describe something entirely their own."
        },
        recoveryOpener: { _ in
            Localized.Onboarding.Chat.useCasePrompt
        },
        store: { value, reason, data, _ in
            if !value.trimmingCharacters(in: .whitespaces).isEmpty {
                data.stylePreference = value
                data.stylePreferenceReason = reason
            }
        },
        isComplete: { $0.stylePreference != nil }
    )

    /// Collects the user's priority — maps to app settings.
    private static let priorityStage = OnboardingStage(
        id: "priority",
        extractor: OnboardingExtractor(
            tag: "priority",
            description: "the user's top priority (one of: power, speed, freedom or privacy) for the AI",
            examples: [
                FewShotExample(
                    userMessage: "I really care about convenience, like I want answers instantly.",
                    assistantResponse: "<priority reason=\"User explicitly values speed\">speed</priority>"
                ),
                FewShotExample(
                    userMessage: "Privacy is my number one concern.",
                    assistantResponse: "<priority reason=\"User explicitly values privacy\">privacy</priority>"
                ),
                FewShotExample(
                    userMessage: "I just want the smartest model available.",
                    assistantResponse: "<priority reason=\"User wants smarts/capability\">power</priority>"
                ),
                FewShotExample(
                    userMessage: "I'd like to use my own API keys and tools.",
                    assistantResponse: "<priority reason=\"User values flexibility and bring-your-own\">freedom</priority>"
                ),
                FewShotExample(
                    userMessage: "[Assistant: \"So Privacy matters most?\"] \"Yes, definitely\"",
                    assistantResponse: "<priority reason=\"User confirmed privacy as top priority\">privacy</priority>"
                ),
            ]
        ),
        systemHint: { data, retryCount in
            if retryCount >= 2 {
                return "Briefly acknowledge, then ask directly: Which matters most — Power, Speed, Freedom, or Privacy?"
            }
            if retryCount == 1 {
                return "Respond naturally, then ask again what matters most to them in an AI app: Power, Speed, Freedom, or Privacy?"
            }
            if let name = data.userName {
                return "Respond naturally, then ask \(name) what matters most to them in an AI app: Power (raw capability), Speed (fast responses), Freedom (to use their own tools), or Privacy. This helps configure the app."
            }
            return "Respond naturally, then ask what matters most to them in an AI app: Power (raw capability), Speed (fast responses), Freedom (to use their own tools), or Privacy. This helps configure the app."
        },
        recoveryOpener: { _ in
            Localized.Onboarding.Chat.priorityPrompt
        },
        store: { value, reason, data, _ in
            let lower = value.lowercased()
            for priority in OnboardingPriority.allCases {
                if lower.contains(priority.rawValue) {
                    data.priority = priority
                    data.priorityReason = reason
                    return
                }
            }
        },
        isComplete: { $0.priority != nil }
    )

    /// Lets the model suggest agent names with an emoji and the user pick one.
    private static func agentNameStage(language: AppLanguage) -> OnboardingStage {
        OnboardingStage(
            id: "agentName",
            extractor: OnboardingExtractor(
                tag: "agent_name",
                description: "the name and an emoji representing the agent, separated by the pipe symbol",
                examples: [
                    FewShotExample(
                        userMessage: "Let's go with Apex.",
                        assistantResponse: "<agent_name reason=\"User selected Apex, assigned eagle emoji\">Apex|🦅</agent_name>"
                    ),
                    FewShotExample(
                        userMessage: "[Assistant: \"How about Sage or Ember?\"] \"I like Sage\"",
                        assistantResponse: "<agent_name reason=\"User picked Sage from assistant's suggestions, assigned wise emoji\">Sage|🧙</agent_name>"
                    ),
                    FewShotExample(
                        userMessage: "[Assistant: \"What about Flux?\"] \"Yeah, and use a lightning emoji\"",
                        assistantResponse: "<agent_name reason=\"User affirmed Flux from assistant's suggestion, assigned lightning emoji\">Flux|⚡</agent_name>"
                    ),
                    FewShotExample(
                        userMessage: "[Assistant: \"How about Apex?\"] \"Actually I want Bob\"",
                        assistantResponse: "<agent_name reason=\"User overrode assistant's suggestion with their own name Bob\">Bob|🧑‍💻</agent_name>"
                    ),
                    FewShotExample(
                        userMessage: "I don't know",
                        assistantResponse: "NONE"
                    ),
                ]
            ),
            systemHint: { data, retryCount in
                let suggestions = AgentNamePool.suggestions(for: language)
                let suggestionText = suggestions.joined(separator: ", ")

                if retryCount >= 2 {
                    return "Briefly acknowledge, then ask directly: Want to pick a name for your personal AI? Here are some ideas: \(suggestionText). Or suggest your own."
                }
                if retryCount == 1 {
                    return "Respond naturally, then suggest more name ideas for their personal AI: \(suggestionText). Ask which one they like, or they can suggest their own."
                }
                if let name = data.userName {
                    return "Respond naturally, then ask \(name) what they'd like to call their personal AI. Suggest these names: \(suggestionText). Or they can suggest their own."
                }
                return "Respond naturally, then explain that their personal AI needs a name. Suggest these names: \(suggestionText). Ask which one they like, or they can suggest their own."
            },
            recoveryOpener: { _ in
                let suggestions = AgentNamePool.suggestions(for: language)
                let suggestionText = suggestions.joined(separator: ", ")
                return Localized.Onboarding.Chat.namePrompt(suggestionText)
            },
            store: { value, reason, data, gaveUp in
                let parts = value.components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                let name = parts[0]
                if !name.isEmpty {
                    data.agentName = name
                    data.agentEmoji = parts.count >= 2 ? parts[1] : "🤖"
                    data.agentNameReason = reason
                } else if gaveUp {
                    data.agentEmoji = "🤖"
                    data.agentName = "Agent"
                }
            },
            isComplete: { $0.agentName != nil && $0.agentEmoji != nil }
        )
    }

    /// Presents a summary of what was learned and asks the user to confirm or correct.
    private static let summaryStage = OnboardingStage(
        id: "summary",
        extractor: OnboardingExtractor(
            tag: "correction",
            description: "any corrections the user wants to make, or NONE if they confirmed",
            examples: [
                FewShotExample(
                    userMessage: "Yes, that's right",
                    assistantResponse: "NONE"
                ),
                FewShotExample(
                    userMessage: "Looks good!",
                    assistantResponse: "NONE"
                ),
                FewShotExample(
                    userMessage: "Actually I prefer detailed responses",
                    assistantResponse: "<correction reason=\"User wants detailed responses instead\">I prefer detailed responses</correction>"
                ),
                FewShotExample(
                    userMessage: "My name is Bob, not Robert",
                    assistantResponse: "<correction reason=\"User's name is Bob, not Robert\">My name is Bob, not Robert</correction>"
                ),
                FewShotExample(
                    userMessage: "I don't know",
                    assistantResponse: "NONE"
                ),
            ]
        ),
        systemHint: { data, _ in
            var summary = "You have everything you need. Briefly summarize what you've learned about the user so far:\n"
            if let name = data.userName {
                let reason = data.userNameReason ?? "they told you"
                summary += "- Their name is \(name) (because \(reason)).\n"
            }
            if let about = data.userAbout {
                let reason = data.userAboutReason ?? "they told you"
                summary += "- They are \(about) (because \(reason)).\n"
            }
            if let context = data.userContext {
                let reason = data.userContextReason ?? "they told you"
                summary += "- They use AI for \(context) (because \(reason)).\n"
            }
            if let style = data.stylePreference {
                let reason = data.stylePreferenceReason ?? "they told you"
                summary += "- They prefer \(style) communication (because \(reason)).\n"
            }
            if let priority = data.priority {
                let reason = data.priorityReason ?? "they told you"
                summary += "- Their top priority is \(priority.rawValue) (because \(reason)).\n"
            }
            summary += "- You are \(data.agentName ?? "Agent").\n"
            summary += "\nAsk if everything looks right or if they'd like to change anything before you set up."
            return summary
        },
        store: { value, reason, data, _ in
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, trimmed.lowercased() != "none" {
                data.summaryCorrection = trimmed
                data.summaryCorrectionReason = reason
            }
        },
        isComplete: { _ in true }
    )
}
