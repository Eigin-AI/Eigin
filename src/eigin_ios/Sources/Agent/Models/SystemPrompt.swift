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
    ///
    /// Takes only the agent — no per-turn state. Everything dynamic (space,
    /// language, intents, skills, hints, interaction mode) is produced by the
    /// ``Gatekeeper`` and appended to the latest user message as an ephemeral
    /// `<system_hint>` block, so this prompt stays byte-identical across turns
    /// and remains cacheable.
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
        Prompt.System.small
    }
}
