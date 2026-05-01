import Foundation

/// Composes an ephemeral `<system_hint>` block from a list of ``SystemHintSource``s.
///
/// The block is rendered as one outer `<system_hint>` tag containing markdown
/// `## Header`-delimited sub-sections in source order. Sources returning `nil`
/// (or an empty string) are skipped, so a source can declare itself inert for
/// a given turn without leaving a stray header or blank line behind.
///
/// If every source returns `nil`, ``build(sources:input:)`` returns `nil` and
/// the caller (``MessagePipeline``) simply does not append anything to the
/// outgoing user message.
enum SystemHintBuilder {
    /// Builds the hint block, or `nil` if every source is silent this turn.
    ///
    /// Iterates sources with `await` so contributors that do I/O (e.g.
    /// ``RelevantKnowledgeSource``) can fetch their data inside `render`.
    @MainActor
    static func build(
        sources: [any SystemHintSource],
        input: SystemHintInput
    ) async -> String? {
        var sections: [String] = []
        for source in sources {
            guard let body = await source.render(input), !body.isEmpty else { continue }
            sections.append("## \(source.title)\n\n\(body)")
        }
        guard !sections.isEmpty else { return nil }
        return "<system_hint>\n" + sections.joined(separator: "\n\n") + "\n</system_hint>"
    }
}
