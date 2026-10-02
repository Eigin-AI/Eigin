@testable import Eigin
import Foundation
import Testing

@Suite("QueryComplexity")
struct QueryComplexityTests {
    // MARK: - Simple messages stay below the bar

    @Test("greetings and short questions stay simple")
    func simpleMessages() {
        #expect(!QueryComplexity.needsReasoning(text: "hi"))
        #expect(!QueryComplexity.needsReasoning(text: "Hej! Hvad er klokken?"))
        #expect(!QueryComplexity.needsReasoning(text: "What's the weather like tomorrow?"))
        #expect(!QueryComplexity.needsReasoning(text: "Thanks, that worked"))
    }

    // MARK: - Weighted threshold

    /// A long, multi-step, technical message — the shape of a dictated work request.
    private static let dictatedWorkRequest = """
    We're planning a full overhaul of our deployment architecture next month, and I \
    want to get ahead of it. First, audit the database migrations across all of our \
    services and list every deviation from our naming conventions, including the file \
    and the line where each one occurs. Then estimate the migration effort for every \
    deviation, rank the results by the risk the change carries, and draft the work \
    items we should file in our tracker, each with reproduction detail, a suggested \
    rollout order, and the owners we should tag. Keep the concurrency implications \
    of every step in mind while you write it all up, and call out anything you would \
    push back on before we commit to the schedule.
    """

    @Test("a long multi-step technical request crosses the threshold")
    func dictatedWorkRequestStepsUp() {
        #expect(QueryComplexity.score(text: Self.dictatedWorkRequest) >= 0.35)
        #expect(QueryComplexity.needsReasoning(text: Self.dictatedWorkRequest))
    }

    @Test("an agentic work instruction steps up")
    func agenticWorkInstruction() {
        // Dictated multi-step instruction to do agentic work: one reasoning marker,
        // a work tool, a multi-step plan — but no code and no question stack.
        let text = """
        Why don't we go ahead and check GitLab? Anything that seems related to that \
        question. We analyze and then we go ahead for step one, do it right, and step \
        two have it awesome, and step three get really into it. But what do you think \
        about models in general? What are we doing here?
        """
        #expect(QueryComplexity.score(text: text) >= 0.35)
        #expect(QueryComplexity.needsReasoning(text: text))
    }

    @Test("casual use of a step signal alone stays simple")
    func casualThenIsNotWork() {
        #expect(!QueryComplexity.needsReasoning(text: "and then we went to lunch"))
    }

    @Test("a single technical word is not enough on its own")
    func oneTechnicalWordIsNotEnough() {
        #expect(!QueryComplexity.needsReasoning(text: "What is encryption?"))
    }

    @Test("code presence plus technical context carries the score")
    func codePresence() {
        let text = """
        This crashes under concurrency on iOS 26 — can you fix it?
        ```swift
        func route(_ request: RouteRequest) async -> ResolvedRoute { … }
        ```
        """
        #expect(QueryComplexity.needsReasoning(text: text))
    }

    // MARK: - The two-marker override

    @Test("two reasoning markers step up regardless of the weighted score")
    func markerOverride() {
        // Short message, weak weighted score — but two markers fire.
        let text = "Analyser this for me, tænk igennem the trade-offs."
        #expect(QueryComplexity.score(text: text) < QueryComplexity.threshold)
        #expect(QueryComplexity.needsReasoning(text: text))
    }

    @Test("one marker alone does not step up")
    func singleMarkerIsNotEnough() {
        #expect(!QueryComplexity.needsReasoning(text: "Figure out who owes what for lunch."))
    }

    // MARK: - Danish

    @Test("Danish markers count like English ones")
    func danishMarkers() {
        let text = """
        Tænk igennem vores arkitektur trin for trin og find ud af, om protokollen \
        er konsistent på tværs af services.
        """
        #expect(QueryComplexity.needsReasoning(text: text))
    }

    // MARK: - Robustness

    @Test("degenerate input never crashes and never steps up")
    func degenerateInput() {
        #expect(!QueryComplexity.needsReasoning(text: ""))
        #expect(!QueryComplexity.needsReasoning(text: " "))
        #expect(!QueryComplexity.needsReasoning(text: "?????"))
    }

    @Test("repeated markers accumulate toward the override")
    func repeatedMarkers() {
        let text = "step by step, and think through each part"
        #expect(QueryComplexity.markerCount(in: text) >= 2)
        #expect(QueryComplexity.needsReasoning(text: text))
    }
}
