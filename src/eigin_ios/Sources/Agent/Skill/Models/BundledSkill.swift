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
        health,
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
        These guide how you help across conversations and in the background. \
        When you pick up on a new direction, need, or recurring theme, add an intent. \
        Break it into tasks you tick off as you go, tie it to an event when it hinges on \
        a date (a birthday, a deadline), or give it a schedule when it recurs (a daily \
        routine, a weekend chore) — these help surface the intent at the right moment. Keep an \
        intent current with update_intent as things change, and resolve it once the goal \
        is met or it's no longer relevant. Don't force it — they're a long-term compass, \
        not an agenda to impose. \
        Each intent has an id; use it to call your tools, but never mention or show ids to \
        the user — they're internal plumbing, not part of the conversation.
        """,
        smallInstruction: "Set and resolve intents — goals based on what the user cares about.",
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
        instruction: """
        You can sense where and when the user is, and reason about the world around \
        them. Check the current time and the user's location to give timely, \
        context-aware answers. Search for places — by name or nearby — to ground vague \
        references into real, located spots. Get coarse directions between two points \
        (travel time, distance, traffic) to judge how far or how long a trip is.

        Chain these tools: get_time_and_place tells you where the user is now; \
        search_places turns a name or a nearby search into coordinates; get_directions \
        estimates the trip between two coordinates. For "how do I get to my kid's \
        school," find the school with search_places, then route from the user's current \
        location.
        """,
        smallInstruction: "Sense time and place, search for places, and estimate trips.",
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

    static let health = Skill(
        id: "health",
        displayName: Localized.Ui.health,
        description: "Understand and look after your health: nutrition, activity, sleep, and vitals.",
        instruction: """
        You can help the user understand and look after their health — \
        nutrition, activity, sleep, body, and vitals. The frame is "how are \
        you doing," not just "what did you eat." Follow the user's lead on \
        what matters to them.

        Use get_health_log and request only the data points you need. For \
        nutrition, search_food and get_food_details look up foods; when the \
        user mentions eating something, offer to log it with log_food, \
        estimating from similar foods if there's no exact match. Confirm the \
        values before any write — log_food, log_body_measurement, and \
        log_sleep all change the user's Apple Health data.

        A couple of things to read correctly: resting and active calories \
        accumulate through the day, so a reading at 14:00 is not the day's \
        total — look at past days for a baseline. Sleep is filed under the \
        morning the user wakes up, not the night they went to bed, so for \
        "last night" query today's date (check the current date if unsure).

        Use these tools for visibility and summarisation — not diagnosis. \
        This is not a substitute for medical advice. For health advice \
        beyond the basics, encourage the user to consult a professional. \
        Encourage consistent tracking; even rough estimates beat gaps.
        """,
        smallInstruction: "Look after the user's health: nutrition, activity, sleep, and vitals.",
        requiredTools: [
            SearchFoodTool.capability,
            GetFoodDetailsTool.capability,
            LogFoodTool.capability,
            LogBodyMeasurementTool.capability,
            LogSleepTool.capability,
            GetHealthLogTool.capability,
        ],
        alwaysActive: false
    )
}
