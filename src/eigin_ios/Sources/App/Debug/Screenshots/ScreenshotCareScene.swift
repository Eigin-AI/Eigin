/// `care` — a hospital appointment with questions to remember. The only scene
/// with option cards: the turn ends on the assistant's question and two cards.
enum ScreenshotCareScene {
    static let chatTitle = "Mum's appointment"

    static var items: [ChatItem] {
        [
            .message(
                id: "care-user",
                role: "user",
                // One line; the answer and cards below need the viewport.
                content: "What do I ask mum's doctor Thursday?"
            ),
            .message(
                id: "care-recall",
                role: "assistant",
                content: """
                You had three concerns: the dosage of the medicine, the \
                dizziness, and the timing.
                """
            ),
            .options(id: "care-options", set: optionSet),
        ]
    }

    /// Closing option cards, exactly like the agent's `present_options` shows.
    static var optionSet: OptionSet {
        OptionSet(
            id: "care-options-set",
            question: "Anything else for Thursday?",
            options: [
                OptionItem(
                    label: "Add a question",
                    description: "Something new to bring up.",
                    category: .care
                ),
                OptionItem(
                    label: "Directions",
                    description: "Route to the hospital, ready in the morning.",
                    category: .move
                ),
            ]
        )
    }
}
