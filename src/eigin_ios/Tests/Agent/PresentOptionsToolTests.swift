@testable import Eigin
import Foundation
import Testing

@Suite("PresentOptionsTool")
@MainActor
struct PresentOptionsToolTests {
    private func execute(_ arguments: String, handler: OptionsHandler? = nil) async -> ToolResult {
        await PresentOptionsTool(onPresentOptions: handler).execute(
            ToolCall(
                id: "options-call",
                type: "function",
                function: .init(name: "present_options", arguments: arguments)
            ),
            agent: Agent(name: "TestAgent", providerID: UUID(), model: "test-model")
        )
    }

    @Test func omittedPresentationDefaultsToCompactAndReturnsSelection() async {
        let result =
            await execute(
                #"{"question":"What next?","options":[{"label":"Walk","description":"Get some fresh air.","category":"move"}]}"#
            ) { set in
                #expect(set.id == "options-call")
                #expect(set.question == "What next?")
                #expect(set.presentation == .compact)
                #expect(set.options.count == 1)
                #expect(set.options.first?.description == "Get some fresh air.")
                #expect(set.options.first?.category == .move)
                return .selected(label: "Walk")
            }
        #expect(!result.isError)
        #expect(result.content.contains("selected"))
        #expect(result.content.contains("Walk"))
    }

    @Test(arguments: ["compact", "visual"])
    func explicitPresentationReachesHandler(_ presentation: String) async {
        let result = await execute("""
        {"presentation":"\(
            presentation
        )","options":[{"label":"Coastal retreat","description":"A quiet week by the sea."}]}
        """) { set in
            #expect(set.presentation.rawValue == presentation)
            #expect(set.options.first?.category == nil)
            return .dismissed
        }
        #expect(!result.isError)
        #expect(result.content.contains("dismissed"))
    }

    @Test(arguments: [
        #"{"options":[{"label":"Walk"}]}"#,
        #"{"options":[{"label":"Walk","description":""}]}"#,
        #"{"options":[{"label":"Walk","description":" \n "}]}"#,
        #"{"options":[{"label":"Walk","description":5}]}"#,
        #"{"options":[{"description":"Fresh air."}]}"#,
        #"{"options":[{"label":" ","description":"Fresh air."}]}"#,
        #"{"options":[{"label":"Walk","description":"Fresh air."},{"label":"Read"}]}"#,
        #"{"presentation":"large","options":[{"label":"Walk","description":"Fresh air."}]}"#,
        #"{"presentation":null,"options":[{"label":"Walk","description":"Fresh air."}]}"#,
        #"{"presentation":7,"options":[{"label":"Walk","description":"Fresh air."}]}"#,
        #"{"options":[]}"#,
        #"{"options":["Walk"]}"#,
        #"{}"#,
        "invalid json",
    ])
    func rejectsInvalidArgumentsWithoutPresenting(_ arguments: String) async {
        let result = await execute(arguments) { _ in
            Issue.record("Invalid options must not reach the presentation handler")
            return .dismissed
        }
        #expect(result.isError)
    }

    @Test func unavailableInteractionReturnsError() async {
        let result = await execute(#"{"options":[{"label":"Walk","description":"Fresh air."}]}"#)
        #expect(result.isError)
        #expect(result.content.contains("not able to interact"))
    }
}
