@testable import Eigin
import Foundation
import Testing

@Suite("ToolCallAccumulator")
struct ToolCallAccumulatorTests {
    @Test func singleToolCallAssembledFromMultipleDeltas() {
        var acc = ToolCallAccumulator()

        // First delta: id and function name
        acc.feed(ToolCallDelta(
            index: 0,
            id: "call_1",
            type: "function",
            function: .init(name: "read_core", arguments: "{\"cor"),
            extraContent: nil
        ))

        // Second delta: more arguments
        acc.feed(ToolCallDelta(
            index: 0,
            id: nil,
            type: nil,
            function: .init(name: nil, arguments: "e\":\"identity\"}"),
            extraContent: nil
        ))

        let calls = acc.finalize()
        #expect(calls.count == 1)
        #expect(calls[0].id == "call_1")
        #expect(calls[0].type == "function")
        #expect(calls[0].function.name == "read_core")
        #expect(calls[0].function.arguments == "{\"core\":\"identity\"}")
    }

    @Test func multipleToolCallsAccumulatedByIndex() {
        var acc = ToolCallAccumulator()

        acc.feed(ToolCallDelta(
            index: 0, id: "call_1", type: "function",
            function: .init(name: "read_core", arguments: "{\"core\":\"identity\"}"),
            extraContent: nil
        ))
        acc.feed(ToolCallDelta(
            index: 1, id: "call_2", type: "function",
            function: .init(name: "set_presentation", arguments: "{\"emoji\":\"🧠\"}"),
            extraContent: nil
        ))

        let calls = acc.finalize()
        #expect(calls.count == 2)
        #expect(calls[0].id == "call_1")
        #expect(calls[0].function.name == "read_core")
        #expect(calls[1].id == "call_2")
        #expect(calls[1].function.name == "set_presentation")
    }

    @Test func finalizeClearsState() {
        var acc = ToolCallAccumulator()

        acc.feed(ToolCallDelta(
            index: 0, id: "call_1", type: "function",
            function: .init(name: "read_core", arguments: "{}"),
            extraContent: nil
        ))

        let first = acc.finalize()
        #expect(first.count == 1)

        let second = acc.finalize()
        #expect(second.isEmpty)
    }
}
