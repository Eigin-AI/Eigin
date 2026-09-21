@testable import Eigin
import Foundation
import MCP
import Testing

@Suite("MCPToolProxy Argument Parsing")
struct MCPToolProxyTests {
    @Test func decodesBooleansAsBooleans() {
        let args = MCPToolProxy.decodeArguments(#"{"confirm": true, "dry_run": false}"#)

        #expect(args?["confirm"] == .bool(true))
        #expect(args?["dry_run"] == .bool(false))
    }

    @Test func decodesNumbers() {
        let args = MCPToolProxy.decodeArguments(#"{"count": 3, "ratio": 0.5}"#)

        #expect(args?["count"] == .int(3))
        #expect(args?["ratio"] == .double(0.5))
    }

    @Test func decodesNestedStructures() {
        let args = MCPToolProxy.decodeArguments(
            #"{"options": {"enabled": true, "retries": 2}, "tags": ["a", false]}"#
        )

        #expect(args?["options"] == .object([
            "enabled": .bool(true),
            "retries": .int(2),
        ]))
        #expect(args?["tags"] == .array([.string("a"), .bool(false)]))
    }

    @Test func keepsDataURLStringsIntact() {
        let args = MCPToolProxy.decodeArguments(
            #"{"image": "data:image/png;base64,iVBORw0KGgo="}"#
        )

        // Value decodes data URLs as .data but re-encodes identically,
        // so the server receives the same string the model sent.
        let reencoded = args.flatMap { try? JSONEncoder().encode($0) }
        let roundTripped = reencoded.flatMap {
            try? JSONDecoder().decode([String: Value].self, from: $0)
        }
        #expect(roundTripped == args)
    }

    @Test func returnsNilForInvalidJSON() {
        #expect(MCPToolProxy.decodeArguments("not json") == nil)
        #expect(MCPToolProxy.decodeArguments("") == nil)
    }
}
