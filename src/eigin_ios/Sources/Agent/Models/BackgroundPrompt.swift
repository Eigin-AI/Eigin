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
        // Background context (moment + proactivity)
        let context: String = switch proactivity {
        case .reactive: Prompt.Background.contextReactive
        case .balanced: Prompt.Background.contextBalanced
        case .proactive: Prompt.Background.contextProactive
        }

        // Intents section
        var intentsLines: [String] = []
        if !activeIntents.isEmpty {
            for intent in activeIntents {
                let days = Int(Date.now.timeIntervalSince(intent.createdAt) / 86400)
                var detail = "\(days) \(days == 1 ? "day" : "days")"
                if let cue = IntentDigest.summary(for: intent) {
                    detail += ", \(cue)"
                }
                intentsLines.append(Prompt.Background.intentItem(
                    content: intent.content,
                    detail: detail
                ))
                for task in intent.tasks.filter({ !$0.completed }) {
                    let label = task.content.count > 50
                        ? task.content.prefix(50) + "…"
                        : Substring(task.content)
                    intentsLines.append(Prompt.Background.taskItem(label: String(label)))
                }
            }
        }

        // Notifications section
        var notificationsLines: [String] = []
        if !recentNotifications.isEmpty {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            for notification in recentNotifications {
                notificationsLines.append(Prompt.Background.notificationItem(
                    when: formatter.string(from: notification.createdAt),
                    title: notification.title,
                    message: notification.message
                ))
            }
        }

        let modeText: String = switch mode {
        case .initiative: Prompt.Background.initiative
        case .maintenance: Prompt.Background.maintenance
        }

        var prompt = Prompt.Background.main(
            name: agent.name,
            emoji: agent.emoji,
            identity: agent.identityCore,
            soul: agent.soulCore,
            user: agent.userCore,
            language: "",
            context: context,
            intentsSection: intentsLines.joined(separator: "\n"),
            notificationsSection: notificationsLines.joined(separator: "\n"),
            mode: modeText
        )

        let skills = activeSkills.isEmpty ? BundledSkill.alwaysActive : activeSkills
        for skill in skills {
            prompt += "\n\n" + skill.instruction
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return prompt
    }
}
