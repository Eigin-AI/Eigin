import Foundation

/// Turns an ``OnboardingAssessment/Result`` and the number of exchanges so far
/// into a `<system_hint>` for the conversation agent, and decides when to force
/// the wrap-up. The agent owns the pacing; this nudges it and guarantees the
/// conversation can't run forever.
struct OnboardingPacing {
    /// User exchanges allowed before the wrap-up is forced. Leaves room for the
    /// agent to ask permission and then seal on the following turn.
    var maxTurns: Int = 10

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

        if result.sentiment == .reluctant {
            parts.append(
                "The user seems reluctant to share more. Don't push — work with "
                    + "what you have and move toward wrapping up."
            )
        }

        if remaining <= 1 {
            parts.append(
                "This is your last message. Propose your name and identity now "
                    + "with set_presentation, then call done."
            )
        } else if remaining <= 2 || result.readiness >= 0.7 {
            if missing.isEmpty {
                parts.append(
                    "You have what you need. Propose who you should be and wrap up "
                        + "within about \(remaining) more exchange(s)."
                )
            } else {
                parts.append(
                    "About \(remaining) exchange(s) left. Still to establish: "
                        + missing.joined(separator: "; ") + ". Start converging."
                )
            }
        } else if !missing.isEmpty {
            parts.append("Still to learn: " + missing.joined(separator: "; ") + ".")
        }

        return parts.joined(separator: "\n")
    }
}
