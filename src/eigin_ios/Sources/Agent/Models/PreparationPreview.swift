import Foundation

/// Shares a bounded prompt budget across ranked goals, task previews, and upcoming initiatives.
enum PreparationPreview {
    static let maxCharacters = 12000

    static func render(intents: [IntentSnapshot], upcoming: [String]) -> String {
        var remaining = maxCharacters - 400
        var initiativeBudget = remaining / 3
        var upcomingLines: [String] = []
        for value in upcoming.prefix(20) {
            let line = String(value.prefix(500))
            guard line.count + 1 <= initiativeBudget else { break }
            upcomingLines.append(line)
            remaining -= line.count + 1
            initiativeBudget -= line.count + 1
        }
        var lines: [String] = []
        var includedIntents = 0
        var includedTasks = 0
        for intent in intents {
            let header = Prompt.Background.intentItem(
                content: "[\(intent.id)] " + String(intent.content.prefix(600)),
                detail: String((IntentDigest.summary(for: intent) ?? "").prefix(160))
            )
            guard header.count + 1 <= remaining else { break }
            lines.append(header)
            remaining -= header.count + 1
            includedIntents += 1
            for task in intent.tasks.lazy.filter({ !$0.completed }).prefix(3) {
                let line = Prompt.Background.taskItem(label: String(task.content.prefix(100)))
                guard line.count + 1 <= remaining else { break }
                lines.append(line)
                remaining -= line.count + 1
                includedTasks += 1
            }
        }
        let totalTasks = intents.reduce(0) { $0 + $1.tasks.count(where: { !$0.completed }) }
        return Prompt.Background.preparationPreview(
            upcoming: upcomingLines.joined(separator: "\n"),
            intents: lines.joined(separator: "\n"),
            omittedIntents: String(intents.count - includedIntents),
            omittedTasks: String(totalTasks - includedTasks),
            omittedInitiatives: String(upcoming.count - upcomingLines.count)
        )
    }
}
