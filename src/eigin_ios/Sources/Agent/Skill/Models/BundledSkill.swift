import Foundation

/// Built-in skills that ship with the app.
enum BundledSkill {
    /// All bundled skills.
    static let all: [Skill] = [
        knowledge,
        intents,
        awareness,
        interaction,
        web,
        selfModification,
        email,
        organization,
        scheduling,
        planning,
        health,
        cooking,
        recommendations,
        aula,
    ]

    /// Skills that are active in every chat from the start.
    static let alwaysActive: [Skill] = all.filter(\.alwaysActive)

    /// Look up a bundled skill by ID.
    static func skill(forID id: String) -> Skill? {
        all.first { $0.id == id }
    }

    // MARK: - Always Active

    static let knowledge = Skill(
        id: "knowledge",
        displayName: Localized.Knowledge.sectionTitle,
        description: "Remember and recall information using your knowledge base.",
        instruction: Prompt.Skills.Knowledge.instruction,
        smallInstruction: Prompt.Skills.Knowledge.small,
        requiredTools: [
            SearchKnowledgeTool.capability,
            GetKnowledgeTool.capability,
            AddKnowledgeTool.capability,
            UpdateKnowledgeTool.capability,
            DeleteKnowledgeTool.capability,
            ForgetKnowledgeTool.capability,
            SupersedeKnowledgeTool.capability,
            MergeKnowledgeTool.capability,
            ContestKnowledgeTool.capability,
        ],
        alwaysActive: true
    )

    static let intents = Skill(
        id: "intents",
        displayName: Localized.Agent.intents,
        description: "Set goals and track what matters to the user across conversations.",
        instruction: Prompt.Skills.Intents.instruction,
        smallInstruction: Prompt.Skills.Intents.small,
        requiredTools: [
            AddIntentTool.capability,
            UpdateIntentTool.capability,
            ListIntentsTool.capability,
            ResolveIntentTool.capability,
        ],
        alwaysActive: true
    )

    static let awareness = Skill(
        id: "awareness",
        displayName: Localized.Settings.awareness,
        description: "Know the current time and place, find places, and estimate trips.",
        instruction: Prompt.Skills.Awareness.instruction,
        smallInstruction: Prompt.Skills.Awareness.small,
        requiredTools: [
            GetTimeAndPlaceTool.capability,
            SearchPlacesTool.capability,
            GetDirectionsTool.capability,
        ],
        alwaysActive: true
    )

    static let interaction = Skill(
        id: "interaction",
        displayName: Localized.Ui.interaction,
        description: "Rich interaction tools for presenting choices and collecting input.",
        instruction: Prompt.Skills.Interaction.instruction,
        smallInstruction: Prompt.Skills.Interaction.small,
        requiredTools: [
            PresentOptionsTool.capability,
        ],
        alwaysActive: true
    )

    static let web = Skill(
        id: "web",
        displayName: Localized.Ui.web,
        description: "Search the web and fetch pages for up-to-date information.",
        instruction: Prompt.Skills.Web.instruction,
        smallInstruction: Prompt.Skills.Web.small,
        requiredTools: [
            WebSearchTool.capability,
            WebFetchTool.capability,
        ],
        alwaysActive: true
    )

    // MARK: - On-Demand

    static let selfModification = Skill(
        id: "self_modification",
        displayName: Localized.Ui.selfModification,
        description: "Change your identity, personality, voice, and behavior.",
        instruction: Prompt.Skills.SelfModification.instruction,
        smallInstruction: Prompt.Skills.SelfModification.small,
        requiredTools: [
            ReadCoreTool.capability,
            EditCoreTool.capability,
            GetPresentationTool.capability,
            SetPresentationTool.capability,
            SetProactivityTool.capability,
            ManageVocabularyTool.capability,
        ],
        alwaysActive: false,
        triggers: SkillTriggers(
            byLanguage: [
                .english: ["personality", "voice", "proactivity", "initiative"],
                .danish: ["personlighed", "stemme", "proaktivitet", "initiativ"],
            ]
        )
    )

    static let email = Skill(
        id: "email",
        displayName: Localized.Ui.email,
        description: "Draft and, if connected, read and send email.",
        instruction: Prompt.Skills.Email.instruction,
        smallInstruction: Prompt.Skills.Email.small,
        requiredTools: [],
        requiredCapabilities: [.email],
        alwaysActive: false,
        triggers: SkillTriggers(
            byLanguage: [.danish: ["indboks"]],
            shared: ["email", "inbox", "mail", "gmail"]
        )
    )

    static let aula = Skill(
        id: "aula",
        displayName: Localized.Ui.aula,
        description: "Get school and daycare updates from a connected Aula account.",
        instruction: Prompt.Skills.Aula.instruction,
        smallInstruction: Prompt.Skills.Aula.small,
        requiredTools: [],
        requiredCapabilities: [.aula],
        alwaysActive: false,
        triggers: SkillTriggers(
            byLanguage: [
                .english: ["school", "daycare", "nursery"],
                .danish: ["skole", "institution", "vuggestue", "børnehave"],
            ],
            shared: ["aula"]
        )
    )

    static let organization = Skill(
        id: "organization",
        displayName: Localized.Ui.organization,
        description: "Manage spaces, move chats and browse chat history.",
        instruction: Prompt.Skills.Organization.instruction,
        smallInstruction: Prompt.Skills.Organization.small,
        requiredTools: [
            CreateSpaceTool.capability,
            EditSpaceTool.capability,
            ListSpacesTool.capability,
            MoveChatToSpaceTool.capability,
            ListChatsTool.capability,
            GetChatTranscriptTool.capability,
        ],
        alwaysActive: false,
        triggers: SkillTriggers(
            byLanguage: [
                .english: ["space", "folder", "archive", "transcript"],
                .danish: ["mappe", "arkiv"],
            ]
        )
    )

    static let scheduling = Skill(
        id: "scheduling",
        displayName: Localized.Ui.scheduling,
        description: "Read and manage calendar events and reminders.",
        instruction: Prompt.Skills.Scheduling.instruction,
        smallInstruction: Prompt.Skills.Scheduling.small,
        requiredTools: [
            GetCalendarEventsTool.capability,
            CreateCalendarEventTool.capability,
            ManageCalendarEventTool.capability,
            GetRemindersTool.capability,
            ManageReminderTool.capability,
        ],
        alwaysActive: false,
        triggers: SkillTriggers(
            byLanguage: [
                .english: [
                    "calendar",
                    "meeting",
                    "remind",
                    "reminder",
                    "appointment",
                    "schedule",
                    "event",
                ],
                .danish: ["kalender", "møde", "aftale", "påmindelse", "begivenhed"],
            ]
        )
    )

    static let planning = Skill(
        id: "planning",
        displayName: Localized.Ui.planning,
        description: "Plan an upcoming trip, event, day out, gathering, festival, or conference.",
        instruction: Prompt.Skills.Planning.instruction,
        smallInstruction: Prompt.Skills.Planning.small,
        requiredTools: [
            StartFlowTool.capability,
            AdvanceFlowTool.capability,
            GetCalendarEventsTool.capability,
            CreateCalendarEventTool.capability,
            ManageCalendarEventTool.capability,
            GetRemindersTool.capability,
            ManageReminderTool.capability,
        ],
        alwaysActive: false,
        triggers: SkillTriggers(
            byLanguage: [
                .english: ["trip", "itinerary", "festival", "conference", "gathering"],
                .danish: ["rejse", "tur", "konference"],
            ]
        )
    )

    static let health = Skill(
        id: "health",
        displayName: Localized.Ui.health,
        description: "Understand and look after your health: nutrition, activity, sleep, and vitals.",
        instruction: Prompt.Skills.Health.instruction,
        smallInstruction: Prompt.Skills.Health.small,
        requiredTools: [
            SearchFoodTool.capability,
            GetFoodDetailsTool.capability,
            LogFoodTool.capability,
            LogBodyMeasurementTool.capability,
            LogSleepTool.capability,
            GetHealthLogTool.capability,
        ],
        alwaysActive: false,
        triggers: SkillTriggers(
            byLanguage: [
                .english: ["nutrition", "calories", "workout", "sleep", "weight", "steps"],
                .danish: ["kost", "kalorier", "træning", "søvn", "vægt", "skridt", "helbred"],
            ]
        )
    )

    static let cooking = Skill(
        id: "cooking",
        displayName: Localized.Ui.cooking,
        description: "Decide what to cook and walk through cooking it, step by step.",
        instruction: Prompt.Skills.Cooking.instruction,
        smallInstruction: Prompt.Skills.Cooking.small,
        requiredTools: [
            StartFlowTool.capability,
            AdvanceFlowTool.capability,
        ],
        alwaysActive: false,
        triggers: SkillTriggers(
            byLanguage: [
                .english: ["recipe", "cook", "dinner", "meal", "food"],
                .danish: ["opskrift", "aftensmad", "måltid", "mad"],
            ]
        )
    )

    static let recommendations = Skill(
        id: "recommendations",
        displayName: Localized.Ui.recommendations,
        description: "Find a book, movie, album, or game worth your time.",
        instruction: Prompt.Skills.Recommendations.instruction,
        smallInstruction: Prompt.Skills.Recommendations.small,
        requiredTools: [
            StartFlowTool.capability,
            AdvanceFlowTool.capability,
        ],
        alwaysActive: false,
        triggers: SkillTriggers(
            byLanguage: [
                .english: ["recommend", "book", "movie", "album", "game"],
                .danish: ["anbefal", "bog", "film", "spil"],
            ]
        )
    )
}
