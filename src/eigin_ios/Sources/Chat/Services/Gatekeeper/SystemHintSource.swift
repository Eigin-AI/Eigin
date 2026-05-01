import Foundation

/// A source of per-turn dynamic context that contributes one section to the
/// ``Gatekeeper``'s ephemeral `<system_hint>` block.
///
/// Sources are called once per turn by ``SystemHintBuilder/build(sources:input:)``
/// and are free to hold mutable session-scoped state — for example
/// ``InteractionModeSource`` tracks the last emitted mode so it can switch
/// between a full description and a short reminder, and ``ChatHintSource``
/// tracks whether a hint has already fired in this session.
///
/// Adding a new type of dynamic context is one file: implement this protocol
/// and register the source in the ``Gatekeeper``'s source list. The builder,
/// pipeline wiring, and tests do not need to change.
@MainActor
protocol SystemHintSource: AnyObject {
    /// Stable section heading, rendered as `## {title}` in the block.
    ///
    /// Kept separate from the body so formatting and inter-section spacing
    /// stays uniform across sources.
    var title: String { get }

    /// Returns the markdown body for this section, or `nil` to omit the
    /// section entirely (no header, no blank lines).
    ///
    /// Called once per turn. `nil` vs empty matters: return `nil` when the
    /// source is silent this turn so the builder does not emit a stray header
    /// or dangling newlines. Empty-string bodies are treated the same as `nil`
    /// defensively, but sources should prefer returning `nil`.
    func render(_ input: SystemHintInput) async -> String?
}
