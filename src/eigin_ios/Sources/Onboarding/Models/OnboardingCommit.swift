import Foundation

/// At the end of onboarding the agent commits to a shape in one call: its
/// presentation, its three core texts, and the line it introduces itself with
/// on the reveal. Everything is checked before anything is written.
struct OnboardingCommit: Equatable {
    var name: String
    var emoji: String
    var identity: String
    var user: String
    /// The agent's own additions, placed after the fixed soul template.
    var soul: String
    var introduction: String

    /// Length caps, in characters. Generous next to what the shapes ask for, so
    /// only text that has gone off the rails is refused.
    static let limits: [String: Int] = [
        "name": 40,
        "identity": 800,
        "user": 1200,
        "soul": 700,
        "introduction": 300,
    ]

    /// Words that mean a core text is talking about the machinery, not the person.
    private static let offTopic = [
        "finish_onboarding",
        "edit_core",
        "set_presentation",
        "system_hint",
    ]

    /// Reads and checks a call's arguments. On failure, the errors say what to fix.
    static func parse(_ args: [String: Any]) -> Result<Self, CommitErrors> {
        func text(_ key: String) -> String {
            ((args[key] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let commit = Self(
            name: text("name"),
            emoji: text("emoji"),
            identity: text("identity"),
            user: text("user"),
            soul: text("soul"),
            introduction: text("introduction")
        )
        var errors: [String] = []
        for (key, value) in commit.fields {
            if value.isEmpty {
                errors.append("\(key) is required.")
            } else if let limit = limits[key], value.count > limit {
                errors.append("\(key) is \(value.count) characters; keep it under \(limit).")
            } else if offTopic.contains(where: value.localizedCaseInsensitiveContains) {
                errors.append("\(key) should describe you and the user, not tools or instructions.")
            }
        }
        if !commit.emoji.isEmpty, !commit.emoji.isSingleEmoji {
            errors.append("emoji must be a single emoji.")
        }
        return errors.isEmpty ? .success(commit) : .failure(CommitErrors(messages: errors))
    }

    /// The soul as it is stored: the fixed base values, then the agent's own.
    var composedSoul: String {
        let base = Prompt.Onboarding.Partials.soulTemplate
        return soul.isEmpty ? base : base + "\n\n" + soul
    }

    private var fields: KeyValuePairs<String, String> {
        [
            "name": name,
            "emoji": emoji,
            "identity": identity,
            "user": user,
            "soul": soul,
            "introduction": introduction,
        ]
    }
}

struct CommitErrors: Error, Equatable {
    let messages: [String]
}

private extension String {
    /// One emoji glyph, flags and skin tones included.
    var isSingleEmoji: Bool {
        guard count == 1, let first = unicodeScalars.first else { return false }
        return first.properties.isEmojiPresentation
            || (first.properties.isEmoji && unicodeScalars.count > 1)
    }
}
