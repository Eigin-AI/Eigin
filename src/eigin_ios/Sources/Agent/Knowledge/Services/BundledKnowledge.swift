/// Static .firm source strings bundled with the app.
///
/// These define the knowledge-base ontology (schemas) and any seed entities
/// that ship with the app. Loaded into every ``KnowledgeService`` session before
/// user/agent-created content.
///
/// Each entity has its own source entry (one entity per file) so that
/// every source — bundled or user-created — maps to exactly one entity.
enum BundledKnowledge {
    // MARK: - Well-Known Entity IDs

    /// The agent's own actor entity in the knowledge graph.
    static let agentActorID = "actor.agent"
    /// The user's actor entity in the knowledge graph.
    static let userActorID = "actor.user"
    /// The Eigin app entity in the knowledge graph.
    static let eiginThingID = "thing.eigin"

    // MARK: - Schemas

    static let schemas = """
    schema actor {
        field {
            name = "name"
            type = "string"
            required = true
        }
        field {
            name = "type"
            type = "enum"
            allowed_values = ["human", "ai", "organization", "other"]
            required = false
        }
        field {
            name = "tags"
            type = "list"
            required = false
        }
        field {
            name = "created_at"
            type = "datetime"
            required = false
        }
        field {
            name = "valid_from"
            type = "datetime"
            required = false
        }
        field {
            name = "valid_until"
            type = "datetime"
            required = false
        }
        field {
            name = "relates_to"
            type = "list"
            required = false
        }
        field {
            name = "belongs_to"
            type = "list"
            required = false
        }
        field {
            name = "uses"
            type = "list"
            required = false
        }
        field {
            name = "describes"
            type = "list"
            required = false
        }
    }

    schema thing {
        field {
            name = "name"
            type = "string"
            required = true
        }
        field {
            name = "category"
            type = "enum"
            allowed_values = ["physical", "digital", "place", "service", "concept", "other"]
            required = false
        }
        field {
            name = "tags"
            type = "list"
            required = false
        }
        field {
            name = "created_at"
            type = "datetime"
            required = false
        }
        field {
            name = "valid_from"
            type = "datetime"
            required = false
        }
        field {
            name = "valid_until"
            type = "datetime"
            required = false
        }
        field {
            name = "relates_to"
            type = "list"
            required = false
        }
        field {
            name = "belongs_to"
            type = "list"
            required = false
        }
        field {
            name = "uses"
            type = "list"
            required = false
        }
        field {
            name = "describes"
            type = "list"
            required = false
        }
    }

    schema fact {
        field {
            name = "name"
            type = "string"
            required = false
        }
        field {
            name = "claim"
            type = "string"
            required = true
        }
        field {
            name = "tags"
            type = "list"
            required = false
        }
        field {
            name = "created_at"
            type = "datetime"
            required = false
        }
        field {
            name = "last_verified"
            type = "datetime"
            required = false
        }
        field {
            name = "valid_from"
            type = "datetime"
            required = false
        }
        field {
            name = "valid_until"
            type = "datetime"
            required = false
        }
        field {
            name = "relates_to"
            type = "list"
            required = false
        }
        field {
            name = "belongs_to"
            type = "list"
            required = false
        }
        field {
            name = "uses"
            type = "list"
            required = false
        }
        field {
            name = "describes"
            type = "list"
            required = false
        }
    }

    schema output {
        field {
            name = "name"
            type = "string"
            required = true
        }
        field {
            name = "content"
            type = "string"
            required = true
        }
        field {
            name = "authors"
            type = "list"
            required = false
        }
        field {
            name = "tags"
            type = "list"
            required = false
        }
        field {
            name = "created_at"
            type = "datetime"
            required = false
        }
        field {
            name = "valid_from"
            type = "datetime"
            required = false
        }
        field {
            name = "valid_until"
            type = "datetime"
            required = false
        }
        field {
            name = "relates_to"
            type = "list"
            required = false
        }
        field {
            name = "belongs_to"
            type = "list"
            required = false
        }
        field {
            name = "uses"
            type = "list"
            required = false
        }
        field {
            name = "describes"
            type = "list"
            required = false
        }
    }

    schema note {
        field {
            name = "content"
            type = "string"
            required = true
        }
        field {
            name = "tags"
            type = "list"
            required = false
        }
        field {
            name = "created_at"
            type = "datetime"
            required = false
        }
        field {
            name = "valid_from"
            type = "datetime"
            required = false
        }
        field {
            name = "valid_until"
            type = "datetime"
            required = false
        }
        field {
            name = "relates_to"
            type = "list"
            required = false
        }
        field {
            name = "belongs_to"
            type = "list"
            required = false
        }
        field {
            name = "uses"
            type = "list"
            required = false
        }
        field {
            name = "describes"
            type = "list"
            required = false
        }
    }
    """

    // MARK: - Seed Entities

    private static let seedEntities: [(type: String, id: String, content: String)] = [
        (
            "thing", "eigin",
            """
            thing eigin {
                name = "Eigin"
                category = enum"digital"
                tags = ["eigin", "app"]
                created_at = 2025-03-11
            }
            """
        ),

        (
            "fact", "eigin_is_private_ai",
            """
            fact eigin_is_private_ai {
                name = "Private and Local-First"
                claim = "Eigin is a private, local-first AI app. All data stays on the device."
                source = enum"stated"
                describes = [thing.eigin]
                tags = ["privacy", "private", "local-first", "data", "security"]
                created_at = 2025-03-11
            }
            """
        ),

        (
            "fact", "eigin_bring_your_own_key",
            """
            fact eigin_bring_your_own_key {
                name = "Bring Your Own Key"
                claim = "Eigin is vendor-agnostic. Users bring their own key from any OpenAI-compatible provider."
                source = enum"stated"
                describes = [thing.eigin]
                tags = ["providers", "api key", "vendor", "openai", "compatible"]
                created_at = 2025-03-11
            }
            """
        ),

        (
            "fact", "eigin_voice_is_core",
            """
            fact eigin_voice_is_core {
                name = "Voice Is Core"
                claim = "Voice is a first-class interaction method. Dictation, text-to-speech, and live call mode are always available."
                source = enum"stated"
                describes = [thing.eigin]
                tags = ["voice", "dictation", "tts", "speech", "text-to-speech", "speaking", "listening"]
                created_at = 2025-03-11
            }
            """
        ),

        (
            "fact", "eigin_agent_has_core_texts",
            """
            fact eigin_agent_has_core_texts {
                name = "Core Texts"
                claim = "The agent has three core texts: identity (who it is), user (who it talks to), and soul (its principles). It can read and edit these over time."
                source = enum"stated"
                describes = [thing.eigin]
                tags = ["core", "identity", "soul", "personality", "self"]
                created_at = 2025-03-11
            }
            """
        ),

        (
            "fact", "eigin_spaces_organize_context",
            """
            fact eigin_spaces_organize_context {
                name = "Spaces"
                claim = "Spaces group chats by context and isolate knowledge between domains like work, personal, or projects."
                source = enum"stated"
                describes = [thing.eigin]
                tags = ["spaces", "context", "organization", "isolation", "domains"]
                created_at = 2025-03-11
            }
            """
        ),

        (
            "fact", "eigin_agent_has_initiative",
            """
            fact eigin_agent_has_initiative {
                name = "Initiative"
                claim = "The agent can work proactively in the background, reflecting on past conversations and sharing observations worth hearing."
                source = enum"stated"
                describes = [thing.eigin]
                tags = ["initiative", "proactive", "background", "notifications"]
                created_at = 2025-03-11
            }
            """
        ),

        (
            "fact", "eigin_free_and_open",
            """
            fact eigin_free_and_open {
                name = "Free and Open Source"
                claim = "Eigin is free and open source. The app is funded by providing sovereign AI to institutions."
                source = enum"stated"
                describes = [thing.eigin]
                tags = ["free", "open source", "sovereign", "pricing"]
                created_at = 2025-03-11
            }
            """
        ),

        (
            "fact", "eigin_extends_with_mcp",
            """
            fact eigin_extends_with_mcp {
                name = "MCP Extensions"
                claim = "The agent can be extended with external tools and data sources via MCP (Model Context Protocol) servers."
                source = enum"stated"
                describes = [thing.eigin]
                tags = ["mcp", "tools", "extensions", "integrations", "plugins"]
                created_at = 2025-03-11
            }
            """
        ),

        (
            "fact", "eigin_on_device_processing",
            """
            fact eigin_on_device_processing {
                name = "On-Device Processing"
                claim = "Dictation, text-to-speech, and embeddings all run on-device. The only time data leaves the device is when it goes to the AI model the user chose."
                source = enum"stated"
                describes = [thing.eigin]
                tags = ["privacy", "private", "processing", "on-device", "local", "data", "security"]
                created_at = 2025-03-11
            }
            """
        ),

        (
            "fact", "eigin_agent_has_knowledge",
            """
            fact eigin_agent_has_knowledge {
                name = "Knowledge Base"
                claim = "The agent has a unified knowledge base for everything it has learned. Knowledge is structured as actors (people, organisations, AI agents), things (objects, places, software, concepts), facts (structured truths with a source), outputs (documents and artefacts created together), and notes (lightweight highlights worth remembering). All knowledge is local-first and scoped to spaces."
                source = enum"stated"
                describes = [thing.eigin]
                tags = ["knowledge", "facts", "notes", "actors", "things", "outputs", "learning", "knowledge base"]
                created_at = 2025-03-11
            }
            """
        ),

        (
            "fact", "eigin_live_call",
            """
            fact eigin_live_call {
                name = "Live Call"
                claim = "Live call is a hands-free, walkie-talkie-style conversation mode. It uses the phone's call framework so it works with the screen locked or in the background."
                source = enum"stated"
                describes = [thing.eigin]
                tags = ["voice", "live call", "call", "hands-free", "phone"]
                created_at = 2025-03-11
            }
            """
        ),

        (
            "fact", "eigin_compaction",
            """
            fact eigin_compaction {
                name = "Context Compaction"
                claim = "When conversations get long, context is automatically compressed so the conversation can continue indefinitely without losing important information."
                source = enum"stated"
                describes = [thing.eigin]
                tags = ["conversation", "context", "compression", "long conversations"]
                created_at = 2025-03-11
            }
            """
        ),

        (
            "fact", "eigin_proactivity_levels",
            """
            fact eigin_proactivity_levels {
                name = "Proactivity Levels"
                claim = "There are three proactivity levels: reactive (no background activity), balanced (occasional valuable insights), and proactive (frequent observations). The agent can ask to adjust its level, or the user can set it directly."
                source = enum"stated"
                describes = [thing.eigin]
                relates_to = [fact.eigin_agent_has_initiative]
                tags = ["proactivity", "initiative", "background", "reactive", "balanced", "proactive", "settings"]
                created_at = 2025-03-11
            }
            """
        ),

        (
            "fact", "eigin_tool_permissions",
            """
            fact eigin_tool_permissions {
                name = "Tool Permissions"
                claim = "Users control what the agent can do through tool permissions: Always (no confirmation), Ask (confirm each time), or Never (disabled). Permissions can be set globally, or per chat."
                source = enum"stated"
                describes = [thing.eigin]
                tags = ["permissions", "tools", "privacy", "security", "control", "confirmation", "settings", "trust"]
                created_at = 2025-03-11
            }
            """
        ),

        (
            "fact", "eigin_language_support",
            """
            fact eigin_language_support {
                name = "Language Support"
                claim = "Eigin is available in multiple languages, currently supporting English and Danish. Language affects dictation, text-to-speech voice, and the interface."
                source = enum"stated"
                describes = [thing.eigin]
                tags = ["language", "languages", "english", "danish", "localization", "dictation", "tts", "interface"]
                created_at = 2025-03-11
            }
            """
        ),

        (
            "fact", "eigin_ai_providers",
            """
            fact eigin_ai_providers {
                name = "AI Providers"
                claim = "Eigin has built-in support for major AI providers including OpenAI, Anthropic, Google, Mistral, and OpenRouter. Users can also connect any OpenAI-compatible endpoint — on-premises, local, American, European, or Chinese. The choice is yours."
                source = enum"stated"
                describes = [thing.eigin]
                relates_to = [fact.eigin_bring_your_own_key]
                tags = ["providers", "models", "api", "service", "openai", "anthropic", "google", "mistral", "openrouter", "local", "on-premises", "vendor"]
                created_at = 2025-03-11
            }
            """
        ),

        (
            "fact", "eigin_agent_self_configurable",
            """
            fact eigin_agent_self_configurable {
                name = "Self-Configurable"
                claim = "The agent can configure itself. You can ask it to change its personality, change its presentation, and modify its own settings. If you want something changed, just ask."
                source = enum"stated"
                describes = [thing.eigin]
                relates_to = [fact.eigin_agent_has_core_texts, fact.eigin_proactivity_levels]
                tags = ["configure", "settings", "self", "customize", "personality", "voice", "avatar", "presentation", "core texts", "autonomy"]
                created_at = 2025-03-11
            }
            """
        ),

        (
            "fact", "eigin_cost_model",
            """
            fact eigin_cost_model {
                name = "Cost Model"
                claim = "Eigin is free — there is no subscription and no service fee. Users pay their AI provider directly on a pay-as-you-go basis. This is great for light use but can exceed typical subscription costs for power users, because API pricing reflects the true cost of AI, not venture-capital-subsidized rates. Users should monitor their provider spending, choose cost-effective models, and set spend limits. The upside: you can switch to a cheaper or better-suited provider at any time."
                source = enum"stated"
                describes = [thing.eigin]
                relates_to = [fact.eigin_bring_your_own_key, fact.eigin_ai_providers, fact.eigin_free_and_open]
                tags = ["cost", "pricing", "free", "subscription", "pay-as-you-go", "api", "spend", "budget", "provider", "models"]
                created_at = 2025-03-11
            }
            """
        ),

        (
            "fact", "eigin_vs_openclaw",
            """
            fact eigin_vs_openclaw {
                name = "Eigin vs. Agent Frameworks"
                claim = "Eigin is sometimes compared to OpenClaw and similar open-source AI agent frameworks. Those projects focus on maximum capability — running headless on a computer, executing code, browsing the web, managing files. Eigin takes a different approach: it is a dedicated app, not a command-line tool, and it is deliberate about privacy and security over raw capability. Open-source agent frameworks carry more risk for data loss, security incidents, and unintended actions. Eigin trades some of that power for trust and safety."
                source = enum"stated"
                describes = [thing.eigin]
                relates_to = [fact.eigin_is_private_ai, fact.eigin_respects_os_security]
                tags = ["comparison", "open claw", "agent", "capability", "privacy", "security", "risk", "headless", "command line"]
                created_at = 2025-03-11
            }
            """
        ),

        (
            "fact", "eigin_vs_chatgpt_claude_gemini",
            """
            fact eigin_vs_chatgpt_claude_gemini {
                name = "Eigin vs. ChatGPT, Claude, Gemini"
                claim = "Eigin does many of the same things as ChatGPT, Claude, and Gemini — and in fact lets you use all of them under the hood. The difference is that Eigin is not tied to any one vendor. You can switch providers tomorrow and everything feels the same. It is free and open source, and does not carry the weight of delivering on a venture-capital promise of hypergrowth. It just tries to be a good tool for you to use AI in a way that is secure and responsible."
                source = enum"stated"
                describes = [thing.eigin]
                relates_to = [fact.eigin_bring_your_own_key, fact.eigin_ai_providers, fact.eigin_free_and_open]
                tags = ["comparison", "chatgpt", "claude", "gemini", "vendor", "independent", "open source", "free", "responsible"]
                created_at = 2025-03-11
            }
            """
        ),

        (
            "fact", "eigin_platforms",
            """
            fact eigin_platforms {
                name = "Platform Availability"
                claim = "Eigin is currently available on iOS only. It is not available on macOS, Android, or any other platform yet. More platforms are planned for the future."
                source = enum"stated"
                describes = [thing.eigin]
                tags = ["platform", "ios", "macos", "android", "availability", "devices", "iphone", "ipad"]
                created_at = 2025-03-11
            }
            """
        ),

        (
            "fact", "eigin_respects_os_security",
            """
            fact eigin_respects_os_security {
                name = "iOS Security Model"
                claim = "Eigin respects the iOS security model. It only uses capabilities allowed by the platform, and explicitly asks for user consent before accessing sensitive resources like the microphone, speech recognition, or notifications."
                source = enum"stated"
                describes = [thing.eigin]
                relates_to = [fact.eigin_is_private_ai]
                tags = ["security", "privacy", "permissions", "consent", "ios", "microphone", "notifications", "trust", "sandbox"]
                created_at = 2025-03-11
            }
            """
        ),

        // MARK: Navigation

        (
            "fact", "eigin_app_tabs",
            """
            fact eigin_app_tabs {
                name = "App Tabs"
                claim = "The app has three tabs: Chat, Agent, and Settings. Chat is for conversations. Agent is for configuring and reviewing your personal agent. Settings is for app-level configuration that only the user can control."
                source = enum"stated"
                describes = [thing.eigin]
                tags = ["navigation", "tabs", "layout", "structure", "chat", "agent", "settings"]
                created_at = 2025-03-12
            }
            """
        ),

        (
            "fact", "eigin_chat_tab",
            """
            fact eigin_chat_tab {
                name = "Chat Tab"
                claim = "The Chat tab shows past conversations and spaces. You can filter chats by space, manage spaces, and create new chats. To start a new chat, type in the input bar at the bottom and press the arrow to send."
                source = enum"stated"
                describes = [thing.eigin]
                relates_to = [fact.eigin_app_tabs, fact.eigin_spaces_organize_context]
                tags = ["navigation", "chat", "tab", "conversations", "spaces", "filter", "new chat", "input"]
                created_at = 2025-03-12
            }
            """
        ),

        (
            "fact", "eigin_chat_dictation",
            """
            fact eigin_chat_dictation {
                name = "Chat Dictation"
                claim = "In chat, you can press the microphone button to dictate instead of typing. The app tells the model you are using dictation, so it will help correct spelling and dictation errors. Just talk naturally and let the model figure it out. It can also update its own vocabulary to improve dictation accuracy over time."
                source = enum"stated"
                describes = [thing.eigin]
                relates_to = [fact.eigin_voice_is_core, fact.eigin_chat_tab]
                tags = ["dictation", "microphone", "voice", "spelling", "vocabulary", "accuracy", "chat", "input"]
                created_at = 2025-03-12
            }
            """
        ),

        (
            "fact", "eigin_chat_actions",
            """
            fact eigin_chat_actions {
                name = "Chat Actions"
                claim = "In a chat, press the plus button to access more actions. You can move the chat to a space, or ask the agent to do it for you. You can press the phone button to start a live call. The live call picks up from the current chat history, and when you leave the call, the extended history from the call is added back to the chat."
                source = enum"stated"
                describes = [thing.eigin]
                relates_to = [fact.eigin_chat_tab, fact.eigin_live_call, fact.eigin_spaces_organize_context]
                tags = ["chat", "actions", "plus button", "move", "space", "live call", "phone", "history"]
                created_at = 2025-03-12
            }
            """
        ),

        (
            "fact", "eigin_agent_tab",
            """
            fact eigin_agent_tab {
                name = "Agent Tab"
                claim = "The Agent tab is where you configure your personal agent. You can set its name, emoji, and voice. If you do not like the available voices, you can install more through the Apple settings menu — the app provides instructions. You can also change which AI provider and model the agent uses."
                source = enum"stated"
                describes = [thing.eigin]
                relates_to = [fact.eigin_app_tabs, fact.eigin_ai_providers]
                tags = ["navigation", "agent", "tab", "name", "emoji", "voice", "provider", "model", "configure"]
                created_at = 2025-03-12
            }
            """
        ),

        (
            "fact", "eigin_agent_tab_review",
            """
            fact eigin_agent_tab_review {
                name = "Reviewing Agent Data"
                claim = "In the Agent tab, you can review all the data the agent has stored locally. You can read its core texts — identity, user understanding, and soul document. You can review its full knowledge base — actors, things, facts, outputs, and notes — and edit or delete entries you do not want the agent to have. This gives you full transparency and control over what the agent knows."
                source = enum"stated"
                describes = [thing.eigin]
                relates_to = [fact.eigin_agent_tab, fact.eigin_agent_has_core_texts, fact.eigin_agent_has_knowledge]
                tags = ["agent", "data", "review", "core texts", "knowledge", "edit", "delete", "transparency", "control"]
                created_at = 2025-03-12
            }
            """
        ),

        (
            "fact", "eigin_agent_has_skills",
            """
            fact eigin_agent_has_skills {
                name = "Skills"
                claim = "The agent has skills that give it access to different capabilities. Some skills are always active — like knowledge, intents, awareness, and web search. Others are activated on demand, either by the agent when it recognises the need, or when you ask. On-demand skills include: self-modification (changing identity, voice, personality), email (composing emails), organization (managing spaces and chat history), scheduling (calendar events and reminders), and food (nutrition lookup and logging)."
                source = enum"stated"
                describes = [thing.eigin]
                relates_to = [fact.eigin_agent_has_knowledge, fact.eigin_agent_has_initiative, fact.eigin_agent_self_configurable, fact.eigin_voice_is_core]
                tags = ["skills", "capabilities", "activate", "scheduling", "food", "nutrition", "email", "organization", "web", "knowledge"]
                created_at = 2026-04-12
            }
            """
        ),

        (
            "fact", "eigin_settings_tab",
            """
            fact eigin_settings_tab {
                name = "Settings Tab"
                claim = "The Settings tab contains configuration that only you as the user can change. You can change the app theme and appearance, change the language, set tool permissions for each individual tool, add AI providers, set up MCP server integrations, and access advanced settings for things like logging and troubleshooting."
                source = enum"stated"
                describes = [thing.eigin]
                relates_to = [fact.eigin_app_tabs, fact.eigin_tool_permissions, fact.eigin_ai_providers, fact.eigin_extends_with_mcp, fact.eigin_language_support]
                tags = ["navigation", "settings", "tab", "theme", "appearance", "language", "permissions", "providers", "mcp", "integrations", "advanced"]
                created_at = 2025-03-12
            }
            """
        ),
    ]

    // MARK: - Virtual paths

    /// Path prefix for bundled (read-only) content.
    static let bundledPrefix = "bundled/"

    /// Path prefix for user/agent-created content.
    static let knowledgePrefix = "knowledge/"

    /// Build the virtual path for a single entity source.
    static func entityPath(prefix: String, type: String, id: String) -> String {
        "\(prefix)\(type)/\(id).firm"
    }

    /// All bundled sources: schemas + one source per seed entity.
    static let allSources: [(path: String, content: String)] = {
        var sources: [(path: String, content: String)] = [
            (path: "\(bundledPrefix)schemas.firm", content: schemas),
        ]
        for entity in seedEntities {
            sources.append(
                (
                    path: entityPath(prefix: bundledPrefix, type: entity.type, id: entity.id),
                    content: entity.content
                )
            )
        }
        return sources
    }()
}
