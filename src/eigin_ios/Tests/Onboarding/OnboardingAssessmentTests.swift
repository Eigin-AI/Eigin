@testable import Eigin
import Foundation
import Testing

@Suite("OnboardingAssessment.parse")
struct OnboardingAssessmentParseTests {
    @Test("Parses a clean JSON object")
    func parsesClean() {
        let raw = """
        {"knows_user": true, "knows_identity": false, \
        "pace": "eager", "readiness": 0.4}
        """
        let result = OnboardingAssessment.parse(raw)
        #expect(result?.knowsUser == true)
        #expect(result?.knowsIdentity == false)
        #expect(result?.pace == .eager)
        #expect(result?.readiness == 0.4)
    }

    @Test("Tolerates surrounding prose and code fences")
    func toleratesNoise() {
        let raw = """
        Here is the assessment:
        ```json
        {"knows_user": true, "knows_identity": true, \
        "pace": "steady", "readiness": 0.9}
        ```
        """
        let result = OnboardingAssessment.parse(raw)
        #expect(result?.knowsUser == true)
        #expect(result?.knowsIdentity == true)
        #expect(result?.readiness == 0.9)
    }

    @Test("Defaults missing fields and clamps readiness")
    func defaultsAndClamps() {
        let result = OnboardingAssessment.parse(#"{"readiness": 1.7}"#)
        #expect(result?.knowsUser == false)
        #expect(result?.pace == .steady)
        #expect(result?.readiness == 1.0)
    }

    @Test("Returns nil when there is no JSON object")
    func noJSON() {
        #expect(OnboardingAssessment.parse("I could not assess this.") == nil)
    }

    @Test("Unknown pace falls back to steady")
    func unknownPace() {
        let result = OnboardingAssessment.parse(#"{"pace": "frantic"}"#)
        #expect(result?.pace == .steady)
    }
}

@Suite("OnboardingAssessment.Result")
struct OnboardingAssessmentResultTests {
    @Test("Missing lists only what is not yet known, and never lists values")
    func missing() {
        let result = OnboardingAssessment.Result(
            knowsUser: false,
            knowsIdentity: false,
            pace: .steady,
            readiness: 0.3
        )
        #expect(result.missing.count == 2)
        #expect(!result.missing.joined().lowercased().contains("value"))
    }

    @Test("Fill target starts above the setup baseline and reaches the full ring")
    func fillTarget() {
        #expect(OnboardingAssessment.Result.empty.fillTarget == 0.5)

        let ready = OnboardingAssessment.Result(
            knowsUser: true,
            knowsIdentity: true,
            pace: .steady,
            readiness: 1.0
        )
        #expect(ready.fillTarget == 1.0)
    }
}

@Suite("OnboardingPacing")
struct OnboardingPacingTests {
    let pacing = OnboardingPacing(maxTurns: 6, minTurns: 2)
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
        #expect(hint.contains("finish_onboarding"))
    }

    @Test("Eager pace below the turn floor asks for one more exchange first")
    func eagerBelowFloor() {
        let result = OnboardingAssessment.Result(
            knowsUser: false,
            knowsIdentity: false,
            pace: .eager,
            readiness: 0.2
        )
        let hint = pacing.hint(result: result, turnsTaken: 1, language: language)
        #expect(hint.lowercased().contains("brief"))
        #expect(!hint.contains("finish_onboarding"))
    }

    @Test("Eager pace past the turn floor checks in before sealing")
    func eagerPastFloor() {
        let result = OnboardingAssessment.Result(
            knowsUser: true,
            knowsIdentity: false,
            pace: .eager,
            readiness: 0.5
        )
        let hint = pacing.hint(result: result, turnsTaken: 2, language: language)
        #expect(hint.contains("check in"))
        #expect(!hint.contains("finish_onboarding"))
    }

    @Test("Reluctant pace past the turn floor also checks in")
    func reluctantPastFloor() {
        let result = OnboardingAssessment.Result(
            knowsUser: true,
            knowsIdentity: false,
            pace: .reluctant,
            readiness: 0.5
        )
        let hint = pacing.hint(result: result, turnsTaken: 3, language: language)
        #expect(hint.contains("check in"))
    }

    @Test("The agent can only seal from the third exchange, or when the budget is spent")
    func sealFloor() {
        #expect(!pacing.canCommit(turnsTaken: 1))
        #expect(!pacing.canCommit(turnsTaken: 2))
        #expect(pacing.canCommit(turnsTaken: 3))
        #expect(OnboardingPacing(maxTurns: 2, minTurns: 1).canCommit(turnsTaken: 2))
    }

    @Test("Steady pace with high readiness nudges toward converging")
    func convergeHint() {
        let result = OnboardingAssessment.Result(
            knowsUser: true,
            knowsIdentity: false,
            pace: .steady,
            readiness: 0.8
        )
        let hint = pacing.hint(result: result, turnsTaken: 2, language: language)
        #expect(hint.contains("identity for yourself"))
    }

    @Test("Steady pace early on names what is still unknown")
    func earlyHint() {
        let result = OnboardingAssessment.Result(
            knowsUser: false,
            knowsIdentity: false,
            pace: .steady,
            readiness: 0.1
        )
        let hint = pacing.hint(result: result, turnsTaken: 1, language: language)
        #expect(hint.contains("Still to learn"))
    }
}
