@testable import Eigin
import Foundation
import Testing

@Suite("OnboardingAssessment.parse")
struct OnboardingAssessmentParseTests {
    @Test("Parses a clean JSON object")
    func parsesClean() {
        let raw = """
        {"knows_user": true, "knows_values": false, "knows_identity": false, \
        "sentiment": "engaged", "readiness": 0.4}
        """
        let result = OnboardingAssessment.parse(raw)
        #expect(result?.knowsUser == true)
        #expect(result?.knowsValues == false)
        #expect(result?.knowsIdentity == false)
        #expect(result?.sentiment == .engaged)
        #expect(result?.readiness == 0.4)
    }

    @Test("Tolerates surrounding prose and code fences")
    func toleratesNoise() {
        let raw = """
        Here is the assessment:
        ```json
        {"knows_user": true, "knows_values": true, "knows_identity": true, \
        "sentiment": "neutral", "readiness": 0.9}
        ```
        """
        let result = OnboardingAssessment.parse(raw)
        #expect(result?.knowsUser == true)
        #expect(result?.knowsValues == true)
        #expect(result?.knowsIdentity == true)
        #expect(result?.readiness == 0.9)
    }

    @Test("Defaults missing fields and clamps readiness")
    func defaultsAndClamps() {
        let result = OnboardingAssessment.parse(#"{"readiness": 1.7}"#)
        #expect(result?.knowsUser == false)
        #expect(result?.sentiment == .neutral)
        #expect(result?.readiness == 1.0)
    }

    @Test("Returns nil when there is no JSON object")
    func noJSON() {
        #expect(OnboardingAssessment.parse("I could not assess this.") == nil)
    }

    @Test("Unknown sentiment falls back to neutral")
    func unknownSentiment() {
        let result = OnboardingAssessment.parse(#"{"sentiment": "grumpy"}"#)
        #expect(result?.sentiment == .neutral)
    }
}

@Suite("OnboardingAssessment.Result")
struct OnboardingAssessmentResultTests {
    @Test("Missing lists only what is not yet known")
    func missing() {
        let result = OnboardingAssessment.Result(
            knowsUser: true,
            knowsValues: false,
            knowsIdentity: false,
            sentiment: .engaged,
            readiness: 0.3
        )
        #expect(result.missing.count == 2)
    }

    @Test("Fill target starts above the setup baseline and reaches the full ring")
    func fillTarget() {
        #expect(OnboardingAssessment.Result.empty.fillTarget == 0.5)

        let ready = OnboardingAssessment.Result(
            knowsUser: true,
            knowsValues: true,
            knowsIdentity: true,
            sentiment: .engaged,
            readiness: 1.0
        )
        #expect(ready.fillTarget == 1.0)
    }
}

@Suite("OnboardingPacing")
struct OnboardingPacingTests {
    let pacing = OnboardingPacing(maxTurns: 6)
    let language = "English"

    @Test("Forces finish once the budget is spent")
    func backstop() {
        #expect(pacing.shouldForceFinish(turnsTaken: 5) == false)
        #expect(pacing.shouldForceFinish(turnsTaken: 6) == true)
        #expect(pacing.turnsRemaining(turnsTaken: 8) == 0)
    }

    @Test("Last message hint forces the wrap-up")
    func lastMessageHint() {
        let hint = pacing.hint(result: .empty, turnsTaken: 6, language: language)
        #expect(hint.contains("last message"))
        #expect(hint.contains("done"))
    }

    @Test("Reluctant sentiment tells the agent not to push")
    func reluctantHint() {
        let result = OnboardingAssessment.Result(
            knowsUser: true,
            knowsValues: true,
            knowsIdentity: false,
            sentiment: .reluctant,
            readiness: 0.5
        )
        let hint = pacing.hint(result: result, turnsTaken: 2, language: language)
        #expect(hint.lowercased().contains("reluctant"))
    }

    @Test("High readiness nudges toward converging")
    func convergeHint() {
        let result = OnboardingAssessment.Result(
            knowsUser: true,
            knowsValues: true,
            knowsIdentity: false,
            sentiment: .engaged,
            readiness: 0.8
        )
        let hint = pacing.hint(result: result, turnsTaken: 2, language: language)
        #expect(hint.contains("identity for yourself"))
    }

    @Test("Early on, the hint names what is still unknown")
    func earlyHint() {
        let result = OnboardingAssessment.Result(
            knowsUser: false,
            knowsValues: false,
            knowsIdentity: false,
            sentiment: .neutral,
            readiness: 0.1
        )
        let hint = pacing.hint(result: result, turnsTaken: 1, language: language)
        #expect(hint.contains("Still to learn"))
    }
}
