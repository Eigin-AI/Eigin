import Foundation

/// The copy ladder the figure speaks up with as a wait drags on.
enum ThinkingCopy: CaseIterable, Equatable {
    case thinking
    case stillThinking
    case almostThere
    case takingAWhile
    case sorryForTheWait

    /// Seconds to wait before each rung appears.
    static let thresholds: [TimeInterval] = [4.5, 11, 18, 29, 44]

    /// The rung to show at `t` seconds since the indicator appeared, or nil
    /// while it's still silent.
    static func stage(at t: TimeInterval) -> ThinkingCopy? {
        for (i, threshold) in thresholds.enumerated() where t >= threshold {
            if i + 1 >= thresholds.count || t < thresholds[i + 1] {
                return Self.allCases[i]
            }
        }
        return nil
    }

    var text: String {
        switch self {
        case .thinking: Localized.Chat.Thinking.thinking
        case .stillThinking: Localized.Chat.Thinking.stillThinking
        case .almostThere: Localized.Chat.Thinking.almostThere
        case .takingAWhile: Localized.Chat.Thinking.takingAWhile
        case .sorryForTheWait: Localized.Chat.Thinking.sorryForTheWait
        }
    }
}

/// The copy ladder for the working activity — the agent is forming or
/// running tool calls. Same rhythm as the thinking ladder, different words.
enum WorkingCopy: CaseIterable, Equatable {
    case working
    case stillWorking
    case takingAWhile
    case sorryForTheWait

    /// Seconds to wait before each rung appears.
    static let thresholds: [TimeInterval] = [4.5, 11, 22, 40]

    /// The rung to show at `t` seconds since the activity began, or nil
    /// while it's still silent.
    static func stage(at t: TimeInterval) -> WorkingCopy? {
        for (i, threshold) in thresholds.enumerated() where t >= threshold {
            if i + 1 >= thresholds.count || t < thresholds[i + 1] {
                return Self.allCases[i]
            }
        }
        return nil
    }

    var text: String {
        switch self {
        case .working: Localized.Chat.Working.working
        case .stillWorking: Localized.Chat.Working.stillWorking
        case .takingAWhile: Localized.Chat.Working.takingAWhile
        case .sorryForTheWait: Localized.Chat.Working.sorryForTheWait
        }
    }
}
