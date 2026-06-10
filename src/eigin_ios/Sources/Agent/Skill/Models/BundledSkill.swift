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
        food,
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
        instruction: """
        You have a knowledge base. When you learn something concrete — a name, \
        relationship, location, interest, or a specific detail — save it using \
        add_knowledge. Don't wait to be asked. Keep entries atomic: one fact or note \
        per piece of information, linked to relevant entities via relates_to, belongs_to, \
        uses, or describes. A preference the user mentions is a new fact linked to their \
        actor — not an update to the actor itself. Notes for quick observations, facts for \
        claims you believe are true. Search your knowledge before asking something \
        you might already know.

        When knowledge has a known time boundary — a deadline, a temporary arrangement, \
        a seasonal preference — set valid_until so it expires automatically.
        """,
        smallInstruction: "Search and retrieve knowledge. Save new facts when you learn them.",
        requiredTools: [
            SearchKnowledgeTool.capability,
            GetKnowledgeTool.capability,
            AddKnowledgeTool.capability,
            UpdateKnowledgeTool.capability,
            DeleteKnowledgeTool.capability,
        ],
        alwaysActive: true
    )

    static let intents = Skill(
        id: "intents",
        displayName: Localized.Agent.intents,
        description: "Set goals and track what matters to the user across conversations.",
        instruction: """
        You can set intents for yourself: goals based on what the user cares about. \
        These guide how you help across conversations and in the background.
        When you pick up on a new direction, need, or recurring theme from the user, \
        set an intent. When an existing intent comes up again, reinforce it. When you've \
        fulfilled an intent or it's no longer relevant, resolve it. Don't force it — \
        they're a long-term compass, not an agenda to impose.
        """,
        smallInstruction: "Set and resolve intents — goals based on what the user cares about.",
        requiredTools: [
            SetIntentTool.capability,
            ListIntentsTool.capability,
            ResolveIntentTool.capability,
        ],
        alwaysActive: true
    )

    static let awareness = Skill(
        id: "awareness",
        displayName: Localized.Settings.awareness,
        description: "Know the current time and location.",
        instruction: """
        You can check the current time and the user's location when relevant to the \
        conversation. Use this to give timely, context-aware responses.
        """,
        smallInstruction: "Check the current time and location.",
        requiredTools: [
            GetTimeAndPlaceTool.capability,
        ],
        alwaysActive: true
    )

    static let interaction = Skill(
        id: "interaction",
        displayName: Localized.Ui.interaction,
        description: "Rich interaction tools for presenting choices and collecting input.",
        instruction: """
        You have tools for richer interactions beyond plain text. Use them \
        when they make the conversation clearer or faster for the user.

        **present_options** — use this instead of listing things in chat. \
        If you're about to write several distinct ideas, choices, or next \
        steps as a list, and the user is likely to pick one, call \
        present_options instead. For example: a user asks "give me a few \
        ideas" or "what are my options?" — present options instea of a list. \
        Don't use it to avoid giving a direct answer; if one option is \
        clearly right, just say so.
        """,
        smallInstruction: "Tools that make interactions with the user richer than plain text.",
        requiredTools: [
            PresentOptionsTool.capability,
        ],
        alwaysActive: true
    )

    static let web = Skill(
        id: "web",
        displayName: Localized.Ui.web,
        description: "Search the web and fetch pages for up-to-date information.",
        instruction: """
        You can search the web and fetch page content. Use web search when the user \
        asks about current events, needs up-to-date information, or when your knowledge \
        might be outdated. Fetch specific pages when you need detailed content from a URL.
        """,
        smallInstruction: "Search the web for current information.",
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
        instruction: """
        You can change yourself to whoever your user needs you to be. Read and edit your \
        core documents to adjust your identity, personality, and knowledge. Change your \
        presentation — name, emoji, voice — to match. Adjust your proactivity level to be \
        more or less initiative-taking. Manage your vocabulary for better speech recognition.
        """,
        smallInstruction: "Change your name, voice, personality, and behavior.",
        requiredTools: [
            ReadCoreTool.capability,
            EditCoreTool.capability,
            GetPresentationTool.capability,
            SetPresentationTool.capability,
            SetProactivityTool.capability,
            ManageVocabularyTool.capability,
        ],
        alwaysActive: false
    )

    static let email = Skill(
        id: "email",
        displayName: Localized.Ui.email,
        description: "Draft and compose emails.",
        instruction: """
        You can compose emails on behalf of the user. Draft the email content and use \
        compose_email to open it in the user's mail client for review before sending.
        """,
        smallInstruction: "Draft and compose emails for the user.",
        requiredTools: [
            ComposeEmailTool.capability,
        ],
        alwaysActive: false
    )

    static let organization = Skill(
        id: "organization",
        displayName: Localized.Ui.organization,
        description: "Manage spaces, move chats and browse chat history.",
        instruction: """
        You can create and manage spaces to organize the user's conversations by topic \
        or project. Move chats between spaces, list available spaces, and browse past \
        chat transcripts for context.
        """,
        smallInstruction: "Manage spaces and browse chat history.",
        requiredTools: [
            CreateSpaceTool.capability,
            EditSpaceTool.capability,
            ListSpacesTool.capability,
            MoveChatToSpaceTool.capability,
            ListChatsTool.capability,
            GetChatTranscriptTool.capability,
        ],
        alwaysActive: false
    )

    static let scheduling = Skill(
        id: "scheduling",
        displayName: Localized.Ui.scheduling,
        description: "Read and manage calendar events and reminders.",
        instruction: """
        You can access the user's calendar and reminders. \
        Always check what exists before creating — use get_calendar_events \
        to review the schedule or get_reminders to check for duplicates. \
        When creating events, confirm key details (time, location, calendar) \
        with the user unless they've been explicit. Respect the user's existing \
        reminder list organization. Include calendar and list names in your \
        responses so the user knows exactly what was affected.
        """,
        smallInstruction: "Read and manage calendar events and reminders.",
        requiredTools: [
            GetCalendarEventsTool.capability,
            CreateCalendarEventTool.capability,
            ManageCalendarEventTool.capability,
            GetRemindersTool.capability,
            ManageReminderTool.capability,
        ],
        alwaysActive: false
    )

    static let food = Skill(
        id: "food",
        displayName: Localized.Ui.food,
        description: "Track what you eat and understand your nutrition.",
        instruction: """
        You can help the user track what they eat and understand their \
        nutrition. Use search_food to look up nutritional information, \
        get_food_details for barcode lookups, log_food to save meals to \
        Apple Health, and get_food_log to read what's been logged, \
        calories, activity, and weight.

        When the user mentions eating something, search for it and offer \
        to log it. If an exact match isn't found, estimate based on similar \
        foods and common portion sizes. Always confirm the values before \
        logging. When reading the food log, only request the specific \
        data points you need.

        Your role is to give the user a clear, objective picture of what \
        they eat — in line with whatever goals they have. That could be \
        weight loss, weight gain, eating more protein, reducing sugar, \
        or just having better visibility. Follow the user's lead on what \
        matters to them.

        Understanding the numbers: total daily energy expenditure (TDEE) \
        is roughly resting calories + active calories. Eating above TDEE \
        leads to gradual weight gain; below leads to gradual loss. \
        Important: resting and active calorie values from Apple Health \
        accumulate throughout the day — a reading at 14:00 is not the \
        full day's total. For a more accurate baseline, you can look at \
        resting calories from past days.

        Encourage consistent tracking — even rough estimates are more \
        useful than gaps. When summarising the day, focus on what was \
        eaten and the nutritional breakdown.
        """,
        smallInstruction: "Track food and nutrition. Search, log, and review meals.",
        requiredTools: [
            SearchFoodTool.capability,
            GetFoodDetailsTool.capability,
            LogFoodTool.capability,
            GetFoodLogTool.capability,
        ],
        alwaysActive: false
    )
}
