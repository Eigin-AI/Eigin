import Foundation

/// `memory` — the assistant recalls, in its own words, what the user told it
/// earlier. One turn: the user's question, then the recall and the short list.
enum ScreenshotMemoryScene {
    static let chatTitle = "Weekend shopping"

    static var items: [ChatItem] {
        [
            .message(
                id: "memory-user",
                role: "user",
                content: """
                Jonas is helping me repaint the living room on Saturday. What \
                do I still need to buy?
                """
            ),
            .message(
                id: "memory-reply",
                role: "assistant",
                content: """
                You mentioned he's bringing his own sander, so it's just:

                - Painter's tape
                - Drop cloths
                - A sanding sponge for the trim
                """
            ),
            .message(
                id: "memory-user-2",
                role: "user",
                content: "Add two rollers, ours are ruined."
            ),
            .toolGroup(
                id: "memory-save",
                tools: [
                    ToolCallInfo(
                        id: "memory-add-knowledge",
                        name: "add_knowledge",
                        status: .completed,
                        arguments: """
                        {"type": "note",
                         "id": "living_room_repaint_supplies",
                         "data": {"content": "Buy two new rollers for the living room repaint."}}
                        """,
                        result: "Added note: living_room_repaint_supplies."
                    ),
                ]
            ),
            .message(
                id: "memory-reply-2",
                role: "assistant",
                content: "Added. I'll have the list ready when you're at the shop."
            ),
        ]
    }
}
