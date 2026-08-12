@testable import Eigin
import Foundation
import Testing

@Suite("SkillHydrator")
struct SkillHydratorTests {
    private func skill(
        id: String, displayName: String? = nil, triggers: SkillTriggers,
        requiredCapabilities: Set<Capability> = []
    ) -> Skill {
        Skill(
            id: id, displayName: displayName ?? id, description: id, instruction: id,
            requiredTools: requiredCapabilities.isEmpty ? [SearchKnowledgeTool.capability] : [],
            requiredCapabilities: requiredCapabilities,
            alwaysActive: false,
            triggers: triggers
        )
    }

    @Test func matchesEnglishTrigger() {
        let email = skill(id: "email", triggers: SkillTriggers(shared: ["email", "inbox"]))
        let result = SkillHydrator.matches(userText: "check my email please", candidates: [email])
        #expect(result == ["email"])
    }

    @Test func matchesDanishTriggerViaMultilingualSuperset() {
        let scheduling = skill(
            id: "scheduling",
            triggers: SkillTriggers(byLanguage: [
                .english: ["calendar", "meeting"],
                .danish: ["kalender", "møde"],
            ])
        )
        let result = SkillHydrator.matches(
            userText: "tjek min kalender", candidates: [scheduling]
        )
        #expect(result == ["scheduling"])
    }

    @Test func unrelatedMessageMatchesNothing() {
        let email = skill(id: "email", triggers: SkillTriggers(shared: ["email", "inbox"]))
        let result = SkillHydrator.matches(
            userText: "what's the weather like today", candidates: [email]
        )
        #expect(result.isEmpty)
    }

    @Test func emptyCandidatesMatchesNothing() {
        let result = SkillHydrator.matches(userText: "check my email", candidates: [])
        #expect(result.isEmpty)
    }

    @Test func capLimitsMatchesToTopN() {
        let email = skill(id: "email", triggers: SkillTriggers(shared: ["email"]))
        let cooking = skill(id: "cooking", triggers: SkillTriggers(shared: ["recipe"]))
        let health = skill(id: "health", triggers: SkillTriggers(shared: ["sleep"]))
        let result = SkillHydrator.matches(
            userText: "email recipe sleep",
            candidates: [email, cooking, health],
            cap: 2
        )
        #expect(result.count == 2)
    }

    @Test func alreadyActiveSkillIsExcludedViaCandidateFilter() {
        // SkillHydrator itself doesn't know about active state — callers pass
        // pre-filtered candidates (see SkillCatalog.activatable). Simulate that
        // filtering here: an active skill simply isn't in `candidates`.
        let cooking = skill(id: "cooking", triggers: SkillTriggers(shared: ["recipe"]))
        let result = SkillHydrator.matches(userText: "give me a recipe", candidates: [cooking])
        #expect(result == ["cooking"])

        let result2 = SkillHydrator.matches(userText: "give me a recipe", candidates: [])
        #expect(result2.isEmpty)
    }

    @Test func ambiguousCommonWordsDoNotOverFireByDesign() {
        // Sanity check on the curated bundled triggers: everyday words like
        // "book" a table shouldn't spuriously fire skills unrelated to the
        // intended meaning is a curation concern, not the matcher's — this
        // just checks the matcher only fires on tokens actually present.
        let recommendations = skill(
            id: "recommendations", triggers: SkillTriggers(byLanguage: [.english: [
                "book",
                "movie",
            ]])
        )
        let result = SkillHydrator.matches(
            userText: "let's talk about something else entirely", candidates: [recommendations]
        )
        #expect(result.isEmpty)
    }

    @Test func rankingPrefersMoreDistinctTriggerHits() {
        // email: 2 distinct triggers hit ("email", "inbox"); scheduling: 1 ("calendar");
        // organization: 0. With cap 2, email should outrank scheduling and organization
        // should be dropped even though it's a valid candidate.
        let email = skill(id: "email", triggers: SkillTriggers(shared: ["email", "inbox"]))
        let scheduling = skill(
            id: "scheduling", triggers: SkillTriggers(shared: ["calendar"])
        )
        let organization = skill(
            id: "organization", triggers: SkillTriggers(shared: ["archive"])
        )
        let result = SkillHydrator.matches(
            userText: "check my email inbox and calendar",
            candidates: [email, scheduling, organization],
            cap: 2
        )
        #expect(result == ["email", "scheduling"])
    }

    @Test func matchesImplicitlyOnDisplayNameEvenWithoutExplicitTrigger() {
        // "health" isn't in the curated trigger list below (only "nutrition" is) — the
        // match must come from the skill's own (localized) display name.
        let health = skill(
            id: "health", displayName: "Health", triggers: SkillTriggers(shared: ["nutrition"])
        )
        let result = SkillHydrator.matches(
            userText: "let's talk about my health", candidates: [health]
        )
        #expect(result == ["health"])
    }

    @Test func candidateFilterExcludesCapabilityLessSkill() {
        // Capability gating (email without a connected integration) lives in
        // SkillCatalog.activatable, shared with AvailableSkillsSource.
        let email = skill(
            id: "email", triggers: SkillTriggers(shared: ["email"]),
            requiredCapabilities: [.email]
        )
        let candidates = SkillCatalog.activatable(
            from: [email], activeIDs: [], connectedCapabilities: []
        )
        #expect(candidates.isEmpty)

        let result = SkillHydrator.matches(userText: "check my email", candidates: candidates)
        #expect(result.isEmpty)
    }
}
