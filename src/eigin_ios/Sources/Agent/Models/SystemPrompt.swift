import Foundation

/// Builds the static system prompt injected at the start of every chat turn.
///
/// This prompt is deliberately **byte-stable across turns for a given agent**:
/// only identity, soul, and behavioural guidelines live here, so providers can
/// hit their prefix cache across the whole session. Per-turn dynamic context
/// (intents, skills, language, space, interaction mode, hints) is produced by
/// the ``Gatekeeper`` and appended as a `<system_hint>` block to the latest
/// user message just before sending.
///
/// The prose lives in `design/prompts/system/*.jinja` and is compiled into
/// ``Prompt/System`` at build time; this type only forwards the per-agent
/// fields that plug into it.
enum SystemPrompt {
    /// Full system prompt for normal-context chat turns.
    static func build(for agent: Agent) -> String {
        Prompt.System.main(
            name: agent.name,
            emoji: agent.emoji,
            identity: agent.identityCore,
            soul: agent.soulCore,
            user: agent.userCore
        )
    }

    /// System prompt for small-context models (≤16K) — the Eigin app's
    /// "local mode" framing.
    static func buildSmall(for agent: Agent) -> String {
        Prompt.System.small(
            name: agent.name,
            emoji: agent.emoji,
            identity: agent.identityCore,
            user: agent.userCore
        )
    }
}
