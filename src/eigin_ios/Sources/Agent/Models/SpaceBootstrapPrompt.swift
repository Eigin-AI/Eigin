import Foundation

enum SpaceBootstrapPrompt {
    static func interviewSystemPrompt(for agent: Agent, language: AppLanguage? = nil) -> String {
        var content = SystemPrompt.build(for: agent)

        if let language {
            content += "\n\nThe user prefers you speak in \(language.displayName)."
        }

        content += """
        ---

        The user wants to create a new space — an isolated workspace with its own \
        context and instructions.

        Have a brief conversation to figure out:
        - What is this space for?
        - What name and emoji should it have?
        - Any special instructions or context to keep in mind?
        - Should this space be public or private? Public spaces share their data freely \
        with other spaces. Private spaces keep data created inside hidden from the rest.

        One question at a time. Keep it natural and brief.

        When you have a good sense of it, call `create_space` with the name, emoji, \
        instructions, and privacy setting. Then call `done`.
        """

        return content
    }
}
