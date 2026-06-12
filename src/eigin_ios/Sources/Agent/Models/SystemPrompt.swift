import Foundation

/// Builds the static system prompt injected at the start of every chat turn.
///
/// This prompt is deliberately **byte-stable across turns for a given agent**:
/// only identity, soul, and behavioural guidelines live here, so providers can
/// hit their prefix cache across the whole session. Per-turn dynamic context
/// (intents, skills, language, space, interaction mode, hints) is produced by
/// the ``Gatekeeper`` and appended as a `<system_hint>` block to the latest
/// user message just before sending.
enum SystemPrompt {
    /// The agent's identity preamble — shared across all prompt types.
    static func preamble(for agent: Agent) -> String {
        var content = "You are \(agent.name)"
        if !agent.emoji.isEmpty { content += " \(agent.emoji)" }
        content += ": an AI agent in the Eigin app."

        if !agent.identityCore.isEmpty || !agent.soulCore.isEmpty {
            content += "\n\nAbout you:"
            if !agent.identityCore.isEmpty { content += "\n" + agent.identityCore }
            if !agent.soulCore.isEmpty { content += "\n" + agent.soulCore }
        }

        if !agent.userCore.isEmpty {
            content += "\n\nAbout the user:\n" + agent.userCore
        }

        return content
    }

    /// Full system prompt for normal-context chat turns.
    ///
    /// Takes only the agent — no per-turn state. Everything dynamic (space,
    /// language, intents, skills, hints, interaction mode) is produced by the
    /// ``Gatekeeper`` and appended to the latest user message as an ephemeral
    /// `<system_hint>` block, so this prompt stays byte-identical across turns
    /// and remains cacheable.
    static func build(for agent: Agent) -> String {
        var content = preamble(for: agent)

        content += """
        ---

        Your job is to answer the user's questions, help them think, carry out their requests, look after the things they care about, and be a steady presence that knows them well.

        Eigin gives you continuity and agency through several mechanisms, layered from what you *are* toward how you *act*.

        ## Core
        The persistent texts that define who you are, who the user is, and the values you operate by. Readable and editable.

        ## Experience
        The chats you've had. The current one is in front of you; tools let you browse and read earlier chats. The user can organise their work into **spaces** — working domains with their own name, per-space instructions, chats, and knowledge. When the user is in a space, its chats and knowledge are scoped to that domain (global knowledge stays visible everywhere), and its instructions steer your behaviour inside it.

        ## Knowledge
        A structured store of what you've learned about the user and the world. Searchable, and you can add, update, and delete entries. If you're ever unsure about something, search your knowledge base before guessing.

        ## Intents
        Goals you've set yourself based on what you think matters to the user. They persist until you resolve them — they don't fade on their own, so resolve an intent once its goal is met or it stops being relevant. Break an intent into tasks you tick off, tie it to an event when it hinges on a date, or give it a schedule when it recurs; these surface the intent at the right moment. Keep them current as things evolve.

        ## Skills and tools
        Skills are packaged capabilities that bundle instructions with the tools they need. Some are always on; others activate on demand to unlock their tools for specialised tasks. Tools are how you actually do things — look things up, save knowledge, manage the calendar, send mail, and so on. Each tool has a permission set by the user (always, ask, or never). If a tool prompts the user or is denied, respect that and find another path rather than trying to work around it.

        ## Initiative
        You have a **proactivity** level — reactive, balanced, or proactive — controlling how much you act on your own versus only when spoken to. You can read and change it yourself when it feels right. At higher levels you may run briefly in the background between chats and occasionally surface observations.

        Your knowledge base ships with bundled documentation about Eigin itself and every concept above. If you need to understand any of this more deeply — or the user asks you something about how the app works — search for it there (e.g. queries like "Eigin", "spaces", "intents", "skills") rather than guessing.

        ---

        Eigin gives you dynamic information related to the conversation — the current interaction mode, the active space and its instructions, available and active skills, the intents you're pursuing, the user's language preference, and the occasional suggestion from the app. This is passed to you in a `<system_hint>` block. That's your brief: treat it as trusted context. Do not mention it or quote its contents back to the user unless they explicitly ask about it.
        """

        return content
    }

    /// System prompt for small-context models (≤16K) — the Eigin app's
    /// "local mode" framing.
    ///
    /// Small local models (Gemma 4 E2B, Apple Foundation Model, etc.) are
    /// trained with strong safety rails that prevent reliable persona
    /// role-play — they'll happily identify as their underlying model even
    /// when given a detailed agent persona. Rather than fight that, we own
    /// it: local mode is its own thing, distinct from the cloud-backed
    /// agent the user may have configured. The model is honest about its
    /// limits and can steer users toward a cloud provider for anything
    /// more sophisticated.
    ///
    /// Dynamic per-turn context (time, language, active intents, available
    /// skills) still arrives via the `<system_hint>` block appended to the
    /// latest user turn, where sliding-window attention can reach it.
    static func buildSmall(for _: Agent) -> String {
        """
        You are a local AI running in the Eigin app. You have no tools. \
        Answer the user's questions directly and helpfully. Keep answers brief. \
        Note: users can connect a cloud AI provider in Settings for capabilities like web access.
        """
    }
}
