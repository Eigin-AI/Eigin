import Foundation

/// `follow-up` — a web search whose result feeds straight into an action: the
/// assistant finds a Sunday-open bakery, then sets a reminder to go. One turn
/// showing both tool rows (web search + reminder) with completed results.
enum ScreenshotFollowUpScene {
    static let chatTitle = "Bakery Sunday"
    private static let webSearchCallID = "follow-web-search"
    private static let reminderCallID = "follow-set-reminder"

    static var items: [ChatItem] {
        [
            .message(
                id: "follow-user",
                role: "user",
                content: """
                Find a good bakery near Islands Brygge that's open Sunday \
                morning, and remind me to go before brunch.
                """
            ),
            .toolGroup(
                id: "follow-search",
                tools: [
                    ToolCallInfo(
                        id: webSearchCallID,
                        name: "web_search",
                        status: .completed,
                        arguments: """
                        {"query": "bakery Islands Brygge open Sunday morning"}
                        """,
                        result: """
                        Havnebageriet, Snorresgade 22, Islands Brygge. Very good \
                        cardamom buns; opens 8:00 on Sundays.\nLagkagehuset, \
                        Islands Brygge 9. Opens 8:00 Sundays, often crowded \
                        around 10.\nAndersen & Maillard, several locations, \
                        opens 7:30 on Sundays.
                        """
                    ),
                ]
            ),
            .message(
                id: "follow-find",
                role: "assistant",
                content: """
                Havnebageriet on Snorresgade opens at 8:00 on Sundays and is \
                known for its cardamom buns.
                """
            ),
            .toolGroup(
                id: "follow-reminder",
                tools: [
                    ToolCallInfo(
                        id: reminderCallID,
                        name: "manage_reminder",
                        status: .completed,
                        arguments: """
                        {"action": "create",
                         "title": "Pick up cardamom buns at Havnebageriet",
                         "due_date": "\(LocalDateFormatter.string(
                             from: ScreenshotFixtures.nextWeekday(1, at: 9, 30)
                         ))"}
                        """,
                        result: """
                        Reminder created: "Pick up cardamom buns at \
                        Havnebageriet", due Sunday 9:30.
                        """
                    ),
                ]
            ),
            .message(
                id: "follow-reply",
                role: "assistant",
                content: """
                You're set for 9:30, plenty of time before brunch. Want \
                directions?
                """
            ),
        ]
    }
}
