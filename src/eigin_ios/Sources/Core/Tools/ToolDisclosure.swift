import Foundation

/// Human-readable disclosure of what a tool call will do, shown on the
/// permission sheet so the user reviews the actual action, not just the tool.
///
/// Both parts are optional. A `nil` `actionPhrase` falls back to the generic
/// "wants to use {tool}" wording.
struct ToolDisclosure: Equatable {
    /// Fills "{agent} wants to {actionPhrase}" — e.g. "search the web for".
    var actionPhrase: String?
    /// The agent-composed payload the user should review before approving.
    var detail: Detail?

    /// How a payload is presented on the sheet.
    enum Detail: Equatable {
        /// Short value shown as a quoted, tinted continuation of the sentence.
        case inline(String)
        /// Long value shown in a bounded, scrollable card below the sentence.
        case block(String)
    }
}
