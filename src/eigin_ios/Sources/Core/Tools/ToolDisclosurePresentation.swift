import Foundation

/// Pure presentation logic for a permission prompt.
///
/// Resolves a ``ToolDisclosure`` into one of four render kinds and decides
/// whether an inline value is short enough to stay in-sentence or must promote
/// to a scrollable block. No SwiftUI, so the view and tests share this logic.
struct ToolDisclosurePresentation: Equatable {
    /// Inline values longer than this promote to a scrollable block.
    static let inlineCharacterLimit = 60

    let kind: Kind

    /// The four escalation states, in order.
    enum Kind: Equatable {
        /// No action phrase — "{agent} wants to use {tool}."
        case generic(agent: String, tool: String)
        /// Action phrase, no payload — "{agent} wants to {phrase}."
        case actionOnly(sentence: String)
        /// Short payload shown quoted, in-sentence.
        case inline(sentence: String, value: String)
        /// Long payload shown in a scrollable card below the sentence.
        case block(sentence: String, value: String)
    }

    init(
        agentName: String,
        toolDisplayName: String,
        disclosure: ToolDisclosure?,
        inlineLimit: Int = inlineCharacterLimit
    ) {
        guard let phrase = disclosure?.actionPhrase else {
            kind = .generic(agent: agentName, tool: toolDisplayName)
            return
        }
        let sentence = Localized.Permission.wantsToFormat(agentName, phrase)
        switch disclosure?.detail {
        case .inline(let value) where value.count <= inlineLimit:
            kind = .inline(sentence: sentence, value: value)
        case .inline(let value):
            kind = .block(sentence: sentence, value: value) // promoted on overflow
        case .block(let value):
            kind = .block(sentence: sentence, value: value)
        case nil:
            kind = .actionOnly(sentence: sentence)
        }
    }

    /// The full sentence as plain text (payload included for inline), for
    /// accessibility and tests. Block payloads live in the card, not here.
    var plainSentence: String {
        switch kind {
        case .generic(let agent, let tool):
            "\(Localized.Permission.wantsToUseFormat(agent, tool))."
        case .actionOnly(let sentence):
            "\(sentence)."
        case .inline(let sentence, let value):
            "\(sentence) \"\(value)\"."
        case .block(let sentence, _):
            "\(sentence):"
        }
    }

    /// The payload to render in the scrollable card, if any.
    var blockValue: String? {
        if case .block(_, let value) = kind { return value }
        return nil
    }
}
