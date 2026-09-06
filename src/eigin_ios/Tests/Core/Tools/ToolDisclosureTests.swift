@testable import Eigin
import Foundation
import Testing

@Suite("Tool Disclosure")
struct ToolDisclosureTests {
    private func call(name: String, arguments: String) -> ToolCall {
        ToolCall(
            id: "call_\(name)",
            type: "function",
            function: .init(name: name, arguments: arguments)
        )
    }

    private func inlineValue(_ disclosure: ToolDisclosure?) -> String? {
        if case .inline(let value)? = disclosure?.detail { return value }
        return nil
    }

    // MARK: - WebSearchTool.disclosure

    @Test func webSearchDisclosesQueryInline() {
        let tool = WebSearchTool()
        let disclosure = tool.disclosure(
            for: call(name: "web_search", arguments: "{\"query\":\"best hiking boots\"}")
        )
        #expect(disclosure?.actionPhrase == Localized.Permission.Disclosure.searchWebFor)
        #expect(disclosure?.detail == .inline("best hiking boots"))
    }

    @Test func webSearchDisclosureNilWhenQueryMissing() {
        let tool = WebSearchTool()
        #expect(tool.disclosure(for: call(name: "web_search", arguments: "{}")) == nil)
    }

    @Test func webSearchDisclosureNilWhenQueryEmpty() {
        let tool = WebSearchTool()
        let disclosure = tool.disclosure(
            for: call(name: "web_search", arguments: "{\"query\":\"   \"}")
        )
        #expect(disclosure == nil)
    }

    @Test func webSearchDisclosureNilOnInvalidJSON() {
        let tool = WebSearchTool()
        #expect(tool.disclosure(for: call(name: "web_search", arguments: "not json")) == nil)
    }

    // MARK: - Tier 1 (external)

    @Test func webFetchDisclosesUrlInline() {
        let disclosure = WebFetchTool().disclosure(
            for: call(name: "web_fetch", arguments: "{\"url\":\"https://example.com/page\"}")
        )
        #expect(disclosure?.actionPhrase == Localized.Permission.Disclosure.fetchPageFrom)
        #expect(disclosure?.detail == .inline("https://example.com/page"))
    }

    @Test func emailSendDisclosesRecipientAndBlock() {
        let tool = SendEmailTool(provider: FakeEmailProvider())
        let disclosure = tool.disclosure(for: call(
            name: "email_send",
            arguments: "{\"to\":\"jane@doe.com\",\"subject\":\"Trip\",\"body\":\"Hi Jane\"}"
        ))
        #expect(disclosure?.actionPhrase == Localized.Permission.Disclosure
            .sendEmailTo("jane@doe.com"))
        #expect(disclosure?.detail == .block("Trip\n\nHi Jane"))
    }

    @Test func emailReplyDisclosesBodyBlock() {
        let tool = ReplyEmailTool(provider: FakeEmailProvider())
        let disclosure = tool.disclosure(for: call(
            name: "email_reply",
            arguments: "{\"message_id\":\"m1\",\"body\":\"Sounds good\"}"
        ))
        #expect(disclosure?.actionPhrase == Localized.Permission.Disclosure.replyToEmail)
        #expect(disclosure?.detail == .block("Sounds good"))
    }

    @Test func searchFoodDisclosesQueryInline() {
        let disclosure = SearchFoodTool().disclosure(
            for: call(name: "search_food", arguments: "{\"query\":\"greek yogurt\"}")
        )
        #expect(disclosure?.detail == .inline("greek yogurt"))
    }

    // MARK: - Tier 2 (local writes)

    @Test func reminderActionMapsToPhrase() {
        let tool = ManageReminderTool(reminderService: nil, canPromptUser: false)
        let create = tool.disclosure(for: call(
            name: "manage_reminder",
            arguments: "{\"action\":\"create\",\"title\":\"Call mum\"}"
        ))
        #expect(create?.actionPhrase == Localized.Permission.Disclosure.reminderAdd)
        #expect(create?.detail == .inline("Call mum"))

        let remove = tool.disclosure(for: call(
            name: "manage_reminder", arguments: "{\"action\":\"delete\",\"reminder_id\":\"r1\"}"
        ))
        #expect(remove?.actionPhrase == Localized.Permission.Disclosure.reminderRemove)
        #expect(remove?.detail == nil)
    }

    @Test func bodyMeasurementFormatsWeight() {
        let tool = LogBodyMeasurementTool(healthService: nil, canPromptUser: false)
        let disclosure = tool.disclosure(
            for: call(name: "log_body_measurement", arguments: "{\"weight_kg\":72.5}")
        )
        // Format the expectation the same way so the assertion is locale-independent
        // (the disclosure string is user-facing and uses the current locale's separator).
        #expect(disclosure?.detail == .inline("\(72.5.formatted()) kg"))
    }

    @Test func logFoodIncludesCalories() {
        let tool = LogFoodTool(healthService: nil, canPromptUser: false)
        let disclosure = tool.disclosure(for: call(
            name: "log_food", arguments: "{\"calories\":650,\"meal_name\":\"Lunch\"}"
        ))
        #expect(inlineValue(disclosure) == "Lunch (650 kcal)")
    }

    @Test func logFoodIgnoresMacros() {
        let tool = LogFoodTool(healthService: nil, canPromptUser: false)
        let disclosure = tool.disclosure(for: call(
            name: "log_food",
            arguments: "{\"calories\":650,\"meal_name\":\"Lunch\",\"protein_g\":30}"
        ))
        #expect(inlineValue(disclosure) == "Lunch (650 kcal)")
    }

    @Test func calendarEventIncludesWhenAndLocation() {
        let tool = CreateCalendarEventTool(calendarService: nil, canPromptUser: false)
        let disclosure = tool.disclosure(for: call(
            name: "create_calendar_event",
            arguments: "{\"title\":\"Dentist\",\"start_date\":\"2026-08-21 14:00\",\"end_date\":\"2026-08-21 15:00\",\"location\":\"Main St\"}"
        ))
        let value = inlineValue(disclosure)
        #expect(value?.contains("Dentist") == true)
        #expect(value?.contains("Main St") == true)
    }

    @Test func calendarEventReadsAsWordsNotTimestamps() {
        let tool = CreateCalendarEventTool(calendarService: nil, canPromptUser: false)
        let disclosure = tool.disclosure(for: call(
            name: "create_calendar_event",
            arguments: "{\"title\":\"Dentist\",\"start_date\":\"2026-08-21 14:00\",\"end_date\":\"2026-08-21 15:00\"}"
        ))
        let value = inlineValue(disclosure)
        // The sheet is read by a person, so no machine timestamps.
        #expect(value?.contains("2026-08-21") == false)
        #expect(value?.contains("Aug") == true)
    }

    @Test func calendarEventSameDayRangeShowsTheDateOnce() {
        let tool = CreateCalendarEventTool(calendarService: nil, canPromptUser: false)
        let disclosure = tool.disclosure(for: call(
            name: "create_calendar_event",
            arguments: "{\"title\":\"Dentist\",\"start_date\":\"2026-08-21 14:00\",\"end_date\":\"2026-08-21 15:00\"}"
        ))
        let value = inlineValue(disclosure) ?? ""
        #expect(value.components(separatedBy: "Aug").count - 1 == 1)
    }

    @Test func calendarEventCrossDayRangeShowsBothDates() {
        let tool = CreateCalendarEventTool(calendarService: nil, canPromptUser: false)
        let disclosure = tool.disclosure(for: call(
            name: "create_calendar_event",
            arguments: "{\"title\":\"Conference\",\"start_date\":\"2026-08-21 09:00\",\"end_date\":\"2026-08-23 17:00\"}"
        ))
        let value = inlineValue(disclosure) ?? ""
        #expect(value.components(separatedBy: "Aug").count - 1 == 2)
    }

    @Test func reminderIncludesDueDate() {
        let tool = ManageReminderTool(reminderService: nil, canPromptUser: false)
        let disclosure = tool.disclosure(for: call(
            name: "manage_reminder",
            arguments: "{\"action\":\"create\",\"title\":\"Call mum\",\"due_date\":\"2026-08-21 09:00\"}"
        ))
        let value = inlineValue(disclosure)
        #expect(value?.contains("Call mum") == true)
        #expect(value?.contains("(") == true)
    }

    @Test func logSleepShowsRangeWhenValid() {
        let tool = LogSleepTool(healthService: nil, canPromptUser: false)
        let disclosure = tool.disclosure(for: call(
            name: "log_sleep",
            arguments: "{\"start\":\"2026-08-21 23:00\",\"end\":\"2026-08-22 07:00\"}"
        ))
        #expect(inlineValue(disclosure) != nil)
    }

    @Test func logSleepFallsBackToActionOnlyOnInvalidDates() {
        let tool = LogSleepTool(healthService: nil, canPromptUser: false)
        let disclosure = tool.disclosure(
            for: call(name: "log_sleep", arguments: "{\"start\":\"a\",\"end\":\"b\"}")
        )
        #expect(disclosure?.actionPhrase == Localized.Permission.Disclosure.logSleep)
        #expect(disclosure?.detail == nil)
    }

    @Test func createSpaceUsesNameAndInstructionsBlock() {
        let disclosure = CreateSpaceTool().disclosure(for: call(
            name: "create_space",
            arguments: "{\"name\":\"Work\",\"emoji\":\"\",\"instructions\":\"Stay formal\",\"is_private\":false}"
        ))
        #expect(disclosure?.actionPhrase == Localized.Permission.Disclosure
            .createSpaceNamed("Work"))
        #expect(disclosure?.detail == .block("Stay formal"))
    }

    @Test func editCoreDisclosesNewStringBlock() {
        let disclosure = EditCoreTool().disclosure(for: call(
            name: "edit_core",
            arguments: "{\"core\":\"identity\",\"old_string\":\"a\",\"new_string\":\"b\"}"
        ))
        #expect(disclosure?.actionPhrase == Localized.Permission.Disclosure.updateMemory)
        #expect(disclosure?.detail == .block("b"))
    }

    @Test func setPresentationInlinesNameOrFallsBack() {
        let named = SetPresentationTool(voiceNames: []).disclosure(
            for: call(name: "set_presentation", arguments: "{\"name\":\"Aria\"}")
        )
        #expect(named?.actionPhrase == Localized.Permission.Disclosure.changeNameTo)
        #expect(named?.detail == .inline("Aria"))

        let bare = SetPresentationTool(voiceNames: []).disclosure(
            for: call(name: "set_presentation", arguments: "{\"emoji\":\"\"}")
        )
        #expect(bare?.actionPhrase == Localized.Permission.Disclosure.updateAppearance)
        #expect(bare?.detail == nil)
    }

    // MARK: - Presentation kind (four states)

    @Test func genericKindWhenNoActionPhrase() {
        let p = ToolDisclosurePresentation(
            agentName: "Ford", toolDisplayName: "Calculator", disclosure: nil
        )
        #expect(p.kind == .generic(agent: "Ford", tool: "Calculator"))
        #expect(p.blockValue == nil)
    }

    @Test func actionOnlyKindWhenNoDetail() {
        let p = ToolDisclosurePresentation(
            agentName: "Ford",
            toolDisplayName: "Send Email",
            disclosure: ToolDisclosure(actionPhrase: "draft an email")
        )
        if case .actionOnly = p.kind {} else { Issue.record("expected actionOnly, got \(p.kind)") }
        #expect(p.blockValue == nil)
    }

    @Test func inlineKindForShortValue() {
        let p = ToolDisclosurePresentation(
            agentName: "Ford",
            toolDisplayName: "Web Search",
            disclosure: ToolDisclosure(
                actionPhrase: "search the web for", detail: .inline("hiking boots")
            )
        )
        if case .inline(_, let value) = p.kind {
            #expect(value == "hiking boots")
        } else {
            Issue.record("expected inline, got \(p.kind)")
        }
        #expect(p.blockValue == nil)
    }

    @Test func blockKindForExplicitBlock() {
        let p = ToolDisclosurePresentation(
            agentName: "Ford",
            toolDisplayName: "Send Email",
            disclosure: ToolDisclosure(
                actionPhrase: "send an email to jane@doe.com", detail: .block("Hi Jane…")
            )
        )
        #expect(p.blockValue == "Hi Jane…")
    }

    // MARK: - Inline → block promotion on overflow

    @Test func inlineStaysInlineAtLimit() {
        let value = String(repeating: "a", count: ToolDisclosurePresentation.inlineCharacterLimit)
        let p = ToolDisclosurePresentation(
            agentName: "Ford",
            toolDisplayName: "Web Search",
            disclosure: ToolDisclosure(actionPhrase: "search the web for", detail: .inline(value))
        )
        #expect(p.blockValue == nil)
    }

    @Test func longInlinePromotesToBlock() {
        let value = String(
            repeating: "a", count: ToolDisclosurePresentation.inlineCharacterLimit + 1
        )
        let p = ToolDisclosurePresentation(
            agentName: "Ford",
            toolDisplayName: "Web Search",
            disclosure: ToolDisclosure(actionPhrase: "search the web for", detail: .inline(value))
        )
        #expect(p.blockValue == value)
    }
}
