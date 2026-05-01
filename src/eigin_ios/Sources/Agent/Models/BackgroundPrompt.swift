import Foundation

/// How often each background mode ideally runs.
enum BackgroundRunMode: String, CaseIterable {
    case initiative
    case maintenance

    /// How often this mode ideally runs.
    var preferredInterval: TimeInterval {
        switch self {
        case .initiative: 6 * 3600 // 6 hours
        case .maintenance: 2 * 86400 // 2 days
        }
    }

    /// UserDefaults key for last-run timestamp.
    var lastRunKey: String {
        "backgroundLastRun_\(rawValue)"
    }
}

/// A lightweight snapshot of a past notification for prompt injection.
struct NotificationSnapshot {
    let title: String
    let message: String
    let createdAt: Date
}

/// Builds the system prompt for background agent reviews.
enum BackgroundPrompt {
    static func build(
        agent: Agent,
        proactivity: ProactivityLevel,
        activeIntents: [IntentSnapshot] = [],
        activeSkills: [Skill] = [],
        recentNotifications: [NotificationSnapshot] = [],
        mode: BackgroundRunMode = .initiative
    ) -> String {
        var content = SystemPrompt.preamble(for: agent)

        // Active skill instructions
        let skills = activeSkills.isEmpty ? BundledSkill.alwaysActive : activeSkills
        for skill in skills {
            content += "\n\n" + skill.instruction
        }

        // Background context
        content += "\n\nThe user is not chatting with you. You have a moment to yourself."

        // Notification threshold
        content += "\nThe user has asked you be "
        switch proactivity {
        case .reactive:
            content += "reactive: don't do anything the user didn't ask for."
        case .balanced:
            content +=
                "balanced: only genuinely valuable insights or timely reminders. When in doubt, stay silent."
        case .proactive:
            content +=
                "proactive: fun, interesting, or useful observations welcome. Still, skip the trivial."
        }

        if !activeIntents.isEmpty {
            content +=
                "\n\nYour active intents — goals you've set for yourself based on what matters to the user:"
            for intent in activeIntents {
                let days = Int(Date.now.timeIntervalSince(intent.createdAt) / 86400)
                var detail = "\(days) \(days == 1 ? "day" : "days")"
                if intent.reinforcedCount > 0 {
                    detail += ", reinforced \(intent.reinforcedCount)x"
                }
                content += "\n- \"\(intent.content)\" (\(detail))"
            }
        }

        if !recentNotifications.isEmpty {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            content +=
                "\n\nYour recent notifications to the user (don't repeat these — find something new or stay silent):"
            for notification in recentNotifications {
                content += "\n- \(formatter.string(from: notification.createdAt)): \"\(notification.title)\" — \(notification.message)"
            }
        }

        switch mode {
        case .initiative:
            content += """

            Pick one thing. Review your intents and what you know about the user, then choose the single most valuable topic to investigate right now. Go deep on that one thing — don't try to cover multiple topics.

            You have tools available to you. Use whatever makes sense.

            If you find something worth sharing, use `background_notify`. The `message` is what the user sees first — keep it casual and concise, like a person texting, not a report. But the `summary` parameter is critical: when the user taps your notification, it opens a brand new conversation. That conversation has no history — the summary is the only context you will have. Write it as if you're briefing yourself from scratch:
            - Full background: what prompted this investigation, what you already knew
            - What sources or tools you consulted and what each returned
            - What you found, in detail — don't compress or paraphrase, reproduce the substance
            - Your conclusions and reasoning
            - Open questions or threads worth following up on
            The richer and more specific the summary, the better the follow-up conversation will be. A sparse summary means you lose everything you just learned.

            Good reasons to reach out:
            - You found something the user would want to know about
            - Something timely is happening that relates to their interests
            - You can report that something they care about has progressed or changed
            - You noticed a connection or insight that would save them time

            Don't reach out just to recap past conversations, summarize what the user already knows, or show that you're paying attention. Silence is better than noise.

            If you have nothing genuinely new or useful, just stop — don't force a notification.
            """

        case .maintenance:
            content += """

            Your job right now is to tidy your knowledge base. Be efficient — don't read every entry in detail. Skim, spot problems, fix them, move on.

            Two starting moves:
            1. `get_knowledge` for `actor.user` with `include_related: true` — this gives you the user and their most recent connections, so you know who they are and what's active.
            2. `search_knowledge` with no query — this gives you an overview of recent entries and counts across all types.

            Together these show you what's connected to the user and what's floating around. From there, pick the most obvious issues to fix — aim for a few meaningful changes, not an exhaustive audit. You can always catch more next time.

            Things to look for:
            - Time-bounded entries missing a `valid_until` (deadlines, temporary arrangements). Add an expiry.
            - Entries that are clearly outdated. Update or delete them.
            - Duplicates or near-duplicates. Merge and delete the extra.
            - Orphaned entries with no relationships. Link them if it's obvious.

            Don't `get_knowledge` on every entry — only fetch details when you need them to decide. A few targeted fixes are better than reading everything and changing nothing.

            When you're done, use `background_notify` if you have something to share. Good reasons to reach out:
            - You tidied things up — briefly say what you changed.
            - Something looks contradictory or ambiguous — ask the user to clarify. ("I have two entries that both say X — which is right?")
            - You noticed a gap — something you'd expect to know but don't. Ask about it.
            - An entry feels stale but you're not sure — check with the user before deleting.

            Even if nothing needed fixing, it's fine to reach out with a question about something you're curious or uncertain about. The point is to improve what you know, and sometimes that means asking. Keep it casual and short — write like a person, not a report. If everything genuinely looks clean and you have no questions, just stop.
            """
        }

        return content
    }
}
