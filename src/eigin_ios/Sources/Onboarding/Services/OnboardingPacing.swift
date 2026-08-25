import Foundation

/// Turns an ``OnboardingAssessment/Result`` and the number of exchanges so far
/// into a `<system_hint>` for the conversation agent, and decides when to force
/// the wrap-up. The agent owns the pacing; this nudges it and guarantees the
/// conversation can't run forever.
struct OnboardingPacing {
    /// User exchanges allowed before the wrap-up is forced. Leaves room for the
    /// agent to ask permission and then seal on the following turn.
    var maxTurns: Int = 10

    /// Minimum exchanges before an eager or reluctant pace can seal things.
    /// Guards against wrapping up in error after a single message.
    var minTurns: Int = 2

    func turnsRemaining(turnsTaken: Int) -> Int {
        max(0, maxTurns - turnsTaken)
    }

    /// True once the budget is spent — the next message must conclude.
    func shouldForceFinish(turnsTaken: Int) -> Bool {
        turnsTaken >= maxTurns
    }

    /// The hint injected before the agent's next message.
    func hint(
        result: OnboardingAssessment.Result,
        turnsTaken: Int,
        language: String
    ) -> String {
        var parts = ["Speak in \(language)."]
        let remaining = turnsRemaining(turnsTaken: turnsTaken)
        let missing = result.missing
        let belowFloor = turnsTaken < minTurns

        switch result.pace {
        case .eager, .reluctant:
            if belowFloor {
                parts.append(Prompt.Onboarding.Pacing.eagerBelowFloor)
            } else {
                parts.append(Prompt.Onboarding.Pacing.eagerConverge)
            }

        case .steady:
            if remaining <= 1 {
                parts.append(Prompt.Onboarding.Pacing.steadyLastMessage)
            } else if remaining <= 2 || result.readiness >= 0.7 {
                if missing.isEmpty {
                    parts.append(Prompt.Onboarding.Pacing.steadyReady)
                } else {
                    parts.append(Prompt.Onboarding.Pacing.steadyProgress(
                        remaining: String(remaining),
                        missing: missing.joined(separator: "; ")
                    ))
                }
            } else if !missing.isEmpty {
                parts.append(Prompt.Onboarding.Pacing.steadyEarly(
                    missing: missing.joined(separator: "; ")
                ))
            }
        }

        return parts.joined(separator: "\n")
    }
}
