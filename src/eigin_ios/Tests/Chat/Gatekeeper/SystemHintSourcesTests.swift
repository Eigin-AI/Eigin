@testable import Eigin
import Foundation
import Testing

/// Behaviour tests for the stateless ``SystemHintSource`` conformers:
/// intents, active skills, available skills, space, language.
@Suite("SystemHintSources (stateless)")
@MainActor
struct SystemHintSourcesTests {
    // MARK: - Helpers

    private func intent(_ content: String) -> IntentSnapshot {
        IntentSnapshot(
            id: UUID(),
            content: content,
            status: .active,
            tasks: [],
            events: [],
            schedules: [],
            createdAt: .now,
            updatedAt: .now
        )
    }

    private func skill(
        id: String,
        displayName: String,
        description: String,
        instruction: String = "Instruction body",
        requiredCapabilities: Set<Capability> = [],
        alwaysActive: Bool = false
    ) -> Skill {
        Skill(
            id: id,
            displayName: displayName,
            description: description,
            instruction: instruction,
            requiredTools: [],
            requiredCapabilities: requiredCapabilities,
            alwaysActive: alwaysActive
        )
    }

    private func input(
        space: SpaceSnapshot? = nil,
        language: AppLanguage? = nil,
        activeIntents: [IntentSnapshot] = [],
        activeSkills: [Skill] = [],
        availableSkills: [Skill] = [],
        connectedCapabilities: Set<Capability> = [],
        activeFlow: FlowState? = nil,
        unavailableSkillNotes: [String] = [],
        provider: ProviderSnapshot = ProviderSnapshot(
            name: "Test Provider",
            baseURL: "https://test.example.com"
        ),
        modelID: String = "test-model",
        isSmallContext: Bool = false
    ) -> SystemHintInput {
        SystemHintInput(
            agentID: UUID(),
            bootstrapComplete: true,
            needsCompaction: false,
            hasSpaces: false,
            messages: [],
            space: space,
            spaceID: nil,
            language: language,
            mode: .text,
            activeIntents: activeIntents,
            activeSkills: activeSkills,
            availableSkills: availableSkills,
            connectedCapabilities: connectedCapabilities,
            activeFlow: activeFlow,
            unavailableSkillNotes: unavailableSkillNotes,
            provider: provider,
            modelID: modelID,
            isSmallContext: isSmallContext
        )
    }

    // MARK: - ActiveIntentsSource

    @Test func activeIntentsNilWhenEmpty() async {
        let source = ActiveIntentsSource()
        #expect(await source.render(input(activeIntents: [])) == nil)
    }

    @Test func activeIntentsRendersCompactSummary() async {
        let source = ActiveIntentsSource()
        let intentID = UUID()
        let openIntent = IntentSnapshot(
            id: intentID,
            content: "Launch Eigin's open source initiative — publish the repo under AGPL before the meetup.",
            status: .active,
            tasks: [IntentTask(content: "Finalize repo for public release")],
            events: [],
            schedules: [],
            createdAt: .now,
            updatedAt: .now
        )
        let body = await source.render(input(activeIntents: [
            openIntent,
            intent("Learn Rust"),
        ])) ?? ""
        #expect(body.contains("- Launch Eigin's open source initiative"))
        #expect(body.contains("Next: Finalize repo for public release"))
        // UUID and task-list plumbing stay out of the hint.
        #expect(!body.contains(intentID.uuidString))
        #expect(!body.contains("•"))
        // Footer cues the agent on where ids and detail live.
        #expect(body.contains("list_intents"))
    }

    @Test func activeIntentsOmitsCueAndNextWhenNothingTimely() async {
        let source = ActiveIntentsSource()
        let body = await source.render(input(activeIntents: [intent("Learn Rust")])) ?? ""
        #expect(body.contains("- Learn Rust"))
        #expect(!body.contains("("))
        #expect(!body.contains("Next:"))
    }

    @Test func activeIntentsOmitsNextWhenAllTasksComplete() async {
        let source = ActiveIntentsSource()
        let done = IntentSnapshot(
            id: UUID(),
            content: "Ship the alpha",
            status: .active,
            tasks: [IntentTask(content: "Finalize onboarding", completed: true)],
            events: [],
            schedules: [],
            createdAt: .now,
            updatedAt: .now
        )
        let body = await source.render(input(activeIntents: [done])) ?? ""
        #expect(body.contains("- Ship the alpha"))
        #expect(!body.contains("Next:"))
        #expect(!body.contains("•"))
    }

    @Test func activeIntentsFooterOmittedInCompactMode() async {
        let source = ActiveIntentsSource()
        let body = await source.render(input(
            activeIntents: [intent("Learn Rust")],
            isSmallContext: true
        )) ?? ""
        #expect(body.contains("- Learn Rust"))
        #expect(!body.contains("list_intents"))
    }

    @Test func activeIntentsTruncatesInCompactMode() async {
        let source = ActiveIntentsSource()
        let longContent = String(repeating: "x", count: 200)
        let body = await source.render(input(
            activeIntents: [
                intent(longContent),
                intent("Second"),
                intent("Third"),
                intent("Fourth — should be dropped"),
                intent("Fifth — should be dropped"),
            ],
            isSmallContext: true
        )) ?? ""
        #expect(body.contains("…"))
        #expect(!body.contains("Fourth"))
        #expect(!body.contains("Fifth"))
    }

    @Test func activeIntentsSummaryKeepsFirstSentenceAndDropsRest() {
        let content = "First sentence stays here. Second sentence with detail. Third one too."
        #expect(ActiveIntentsSource.summary(content, limit: 90) == "First sentence stays here.")
    }

    @Test func activeIntentsSummaryFallsBackToHardTruncationWithoutTerminator() {
        let content = String(repeating: "x", count: 120)
        let summary = ActiveIntentsSource.summary(content, limit: 90)
        #expect(summary.count == 90 + 1) // prefix plus ellipsis
        #expect(summary.hasSuffix("…"))
    }

    @Test func activeIntentsSummaryEllipsizesLongFirstSentence() {
        let content = String(repeating: "y", count: 120) + ". Second sentence."
        let summary = ActiveIntentsSource.summary(content, limit: 90)
        #expect(summary.count == 90 + 1)
        #expect(summary.hasSuffix("…"))
    }

    @Test func activeIntentsNextActionTruncatesLongTask() async throws {
        let source = ActiveIntentsSource()
        let longTask = String(repeating: "z", count: 80)
        let snapshot = IntentSnapshot(
            id: UUID(),
            content: "Goal",
            status: .active,
            tasks: [IntentTask(content: longTask)],
            events: [],
            schedules: [],
            createdAt: .now,
            updatedAt: .now
        )
        let body = await source.render(input(activeIntents: [snapshot])) ?? ""
        let nextStart = try #require(body.range(of: "Next: ")).upperBound
        let action = body[nextStart...].prefix(while: { !$0.isNewline })
        // Truncated without exposing internal caps as magic numbers.
        #expect(String(action).hasSuffix("…"))
        #expect(action.count < longTask.count)
    }

    @Test func activeIntentsSummaryCutsLongSingleSentenceAtClauseDash() {
        let content = "Launch the open source initiative — publish the repo under AGPL before the meetup in Copenhagen"
        #expect(ActiveIntentsSource
            .summary(content, limit: 40) == "Launch the open source initiative")
    }

    @Test func activeIntentsSummaryCollapsesNewlinesToOneLine() {
        let content = "Ship the alpha\nwith onboarding done. Keep the rest quiet."
        #expect(ActiveIntentsSource
            .summary(content, limit: 90) == "Ship the alpha with onboarding done.")
    }

    // MARK: - ActiveSkillsSource

    @Test func activeSkillsNilInCompact() async {
        let source = ActiveSkillsSource()
        let body = await source.render(input(
            activeSkills: [skill(id: "a", displayName: "A", description: "d", instruction: "body")],
            isSmallContext: true
        ))
        #expect(body == nil)
    }

    @Test func activeSkillsNilWhenEmpty() async {
        let source = ActiveSkillsSource()
        #expect(await source.render(input(activeSkills: [])) == nil)
    }

    @Test func activeSkillsJoinsInstructionsWithDisplayNameHeaders() async throws {
        let source = ActiveSkillsSource()
        let body = await source.render(input(activeSkills: [
            skill(
                id: "a",
                displayName: "Alpha",
                description: "d",
                instruction: "first instruction"
            ),
            skill(
                id: "b",
                displayName: "Bravo",
                description: "d",
                instruction: "second instruction"
            ),
        ])) ?? ""
        #expect(body.contains("### Alpha"))
        #expect(body.contains("### Bravo"))
        #expect(body.contains("first instruction"))
        #expect(body.contains("second instruction"))
        // Alpha header should precede its instruction.
        let alphaHeaderIdx = try #require(body.range(of: "### Alpha")?.lowerBound)
        let firstInstructionIdx = try #require(body.range(of: "first instruction")?.lowerBound)
        #expect(alphaHeaderIdx < firstInstructionIdx)
    }

    @Test func activeSkillsRendersUnavailableNoteForUnreachableMCPServer() async {
        // An MCP skill stays active even when its server can't be reached this
        // turn — the note surfaces the problem instead of silently dropping it.
        let source = ActiveSkillsSource()
        let body = await source.render(input(
            activeSkills: [skill(
                id: "mcp__gitlab", displayName: "GitLab", description: "d",
                instruction: "Use GitLab tools."
            )],
            unavailableSkillNotes: [
                "GitLab is currently unavailable (Session expired). The user may need to reauthorize it.",
            ]
        )) ?? ""
        #expect(body.contains("### GitLab"))
        #expect(body.contains("currently unavailable"))
    }

    @Test func activeSkillsRendersUnavailableNoteEvenWithNoActiveSkills() async {
        // Edge case: nothing else active, only an unavailable-server note.
        let source = ActiveSkillsSource()
        let body = await source.render(input(
            activeSkills: [],
            unavailableSkillNotes: ["Linear is currently unavailable (Server down)."]
        ))
        #expect(body?.contains("Linear is currently unavailable") == true)
    }

    // MARK: - ActiveFlowSource

    @Test func activeFlowNilWhenNoneActive() async {
        let source = ActiveFlowSource()
        #expect(await source.render(input(activeFlow: nil)) == nil)
    }

    @Test func activeFlowNilInCompact() async {
        let source = ActiveFlowSource()
        let state = FlowState(flowID: "trip", skillID: "planning", stage: 0, notes: [])
        #expect(await source.render(input(activeFlow: state, isSmallContext: true)) == nil)
    }

    @Test func activeFlowRendersCurrentStageAndNudge() async {
        let source = ActiveFlowSource()
        let state = FlowState(
            flowID: "trip",
            skillID: "planning",
            stage: 1,
            notes: ["family of four, Berlin"]
        )
        let body = await source.render(input(activeFlow: state)) ?? ""
        #expect(body.contains("trip"))
        #expect(body.contains("stage 2 of 5"))
        #expect(body.contains("advance_flow"))
    }

    @Test func activeFlowRendersAccumulatedNotesOnShowNotesStage() async {
        let source = ActiveFlowSource()
        // Stage index 4 ("itinerary") has show_notes = true in flows.toml.
        let state = FlowState(
            flowID: "trip",
            skillID: "planning",
            stage: 4,
            notes: ["chose the aquarium"]
        )
        let body = await source.render(input(activeFlow: state)) ?? ""
        #expect(body.contains("chose the aquarium"))
    }

    // MARK: - AvailableSkillsSource

    @Test func availableSkillsExcludesActiveAndAlwaysActive() async {
        let source = AvailableSkillsSource()
        let active = skill(id: "active", displayName: "Active", description: "d")
        let always = skill(
            id: "always",
            displayName: "Always",
            description: "d",
            alwaysActive: true
        )
        let activatable = skill(id: "activatable", displayName: "Activatable", description: "d")

        let body = await source.render(input(
            activeSkills: [active],
            availableSkills: [active, always, activatable]
        )) ?? ""
        #expect(body.contains("Activatable"))
        #expect(!body.contains("Active"))
        #expect(!body.contains("Always"))
    }

    @Test func availableSkillsNilWhenNothingActivatable() async {
        let source = AvailableSkillsSource()
        let always = skill(
            id: "always",
            displayName: "Always",
            description: "d",
            alwaysActive: true
        )
        #expect(await source.render(input(availableSkills: [always])) == nil)
    }

    @Test func availableSkillsTruncatesInCompactMode() async {
        let source = AvailableSkillsSource()
        let longDesc = String(repeating: "y", count: 200)
        let skills = (0 ..< 10).map { i in
            skill(id: "s\(i)", displayName: "S\(i)", description: longDesc)
        }
        let result = await source.render(input(
            availableSkills: skills,
            isSmallContext: true
        ))
        // Small-context models don't receive skill hints at all.
        #expect(result == nil)
    }

    @Test func availableSkillsHidesToollessSkillWithoutConnectedCapability() async {
        let source = AvailableSkillsSource()
        let email = skill(
            id: "email", displayName: "Email", description: "d",
            requiredCapabilities: [.email]
        )
        let result = await source.render(input(availableSkills: [email]))
        #expect(result == nil)
    }

    @Test func availableSkillsShowsToollessSkillWhenCapabilityConnected() async {
        let source = AvailableSkillsSource()
        let email = skill(
            id: "email", displayName: "Email", description: "d",
            requiredCapabilities: [.email]
        )
        let body = await source.render(input(
            availableSkills: [email],
            connectedCapabilities: [.email]
        )) ?? ""
        #expect(body.contains("Email"))
    }

    @Test func availableSkillsFullModeIncludesActivateFooter() async {
        let source = AvailableSkillsSource()
        let body = await source.render(input(
            availableSkills: [skill(id: "s", displayName: "S", description: "d")]
        )) ?? ""
        #expect(body.contains("activate_skill"))
    }

    @Test func availableSkillsIncludesMCPProjectedServerWithNameInstructionsAndTools() async throws {
        // A connected MCP server projects into the same catalog as bundled
        // skills — see #140. Uses the real projection so the catalog entry
        // matches what MCPServerSkill actually produces.
        let server = MCPServer(name: "GitLab", url: "https://example.com")
        server.cachedToolNames = ["list_issues"]
        server.serverInstructions = "Manage GitLab issues and merge requests."
        let mcpSkill = try #require(MCPServerSkill.project(servers: [server]).first)

        let source = AvailableSkillsSource()
        let body = await source.render(input(availableSkills: [mcpSkill])) ?? ""
        #expect(body.contains("GitLab"))
        #expect(body.contains("mcp__gitlab"))
        #expect(body.contains("Manage GitLab issues and merge requests."))
        #expect(body.contains("list_issues"))
    }

    // MARK: - SpaceSource

    @Test func spaceRendersNameAndInstructions() async {
        let source = SpaceSource()
        let body = await source.render(input(
            space: SpaceSnapshot(id: UUID(), name: "Work", instructions: "Focus on code reviews.")
        )) ?? ""
        #expect(body.contains("Work"))
        #expect(body.contains("Focus on code reviews."))
    }

    @Test func spaceNilWhenNoSpace() async {
        #expect(await SpaceSource().render(input(space: nil)) == nil)
    }

    @Test func spaceNilWhenInstructionsEmpty() async {
        let body = await SpaceSource().render(input(
            space: SpaceSnapshot(id: UUID(), name: "Empty", instructions: "")
        ))
        #expect(body == nil)
    }

    @Test func spaceTruncatesInCompact() async throws {
        let longInstructions = String(repeating: "x", count: 200)
        let body = await SpaceSource().render(input(
            space: SpaceSnapshot(id: UUID(), name: "Work", instructions: longInstructions),
            isSmallContext: true
        ))
        // Compact mode renders the space but truncates long instructions.
        #expect(body != nil)
        #expect(try #require(body?.contains("Work")))
        #expect(try #require(body?.count) < longInstructions.count)
    }

    @Test func spaceShortInstructionsNotTruncatedInCompact() async {
        let body = await SpaceSource().render(input(
            space: SpaceSnapshot(id: UUID(), name: "Work", instructions: "Focus."),
            isSmallContext: true
        ))
        #expect(body?.contains("Focus.") == true)
    }

    // MARK: - GeneralInfoSource

    @Test func generalInfoRendersLocalTime() async {
        let fixedDate = Date(timeIntervalSince1970: 1_800_000_000) // 2027-01-15 08:00 UTC
        let source = GeneralInfoSource(now: { fixedDate })
        let body = await source.render(input()) ?? ""
        // Should contain the formatted time string from LocalDateFormatter
        #expect(body.contains("Local time:"))
        #expect(body.contains(LocalDateFormatter.string(from: fixedDate)))
    }

    @Test func generalInfoCompactRendersOneLiner() async {
        let source = GeneralInfoSource(now: { Date() })
        let body = await source.render(input(isSmallContext: true))
        #expect(body != nil)
        #expect(body?.contains("Running locally") == true)
    }

    @Test func generalInfoTitle() {
        #expect(GeneralInfoSource().title == "General info")
    }

    // MARK: - LanguageSource

    @Test func languageRendersPreference() async {
        let body = await LanguageSource().render(input(language: .danish)) ?? ""
        #expect(body.contains("Dansk"))
    }

    @Test func languageNilWhenNotSet() async {
        #expect(await LanguageSource().render(input(language: nil)) == nil)
    }

    @Test func languageStillRendersInCompact() async {
        let body = await LanguageSource().render(input(language: .english, isSmallContext: true))
        #expect(body != nil)
        #expect(body?.contains("English") == true)
    }
}
