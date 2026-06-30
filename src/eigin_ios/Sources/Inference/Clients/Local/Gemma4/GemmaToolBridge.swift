import Foundation
@preconcurrency import LiteRTLM

// Bridges the app's ``ToolDefinition``-based tool system into LiteRT-LM's
// native ``Tool`` protocol, preserving our agentic loop's permission model,
// chat feed rendering, and multi-round execution.
//
// ## Why concrete structs
//
// LiteRT's `ToolManager` decodes tool arguments via `Codable` into `@ToolParam`
// property-wrapper fields on a concrete `Tool` struct, then calls `run()` on
// that decoded instance. There is no way to intercept arguments generically —
// each tool needs its own `@ToolParam` fields matching its schema exactly.
//
// ## How the bridge works
//
// LiteRT owns the tool-call loop: a single `sendMessageStream` drives the whole
// turn. When the model emits a tool call, LiteRT decodes the arguments into the
// concrete struct's `@ToolParam` fields and calls `run()` *inline*, then feeds
// the returned result straight back into the same KV-cached session and keeps
// generating — looping internally for multi-tool turns. The stream the caller
// consumes only finishes when the model truly stops.
//
// `run()` reaches the real Eigin tool through ``GemmaToolBridgeRunner``, a
// turn-scoped holder for the ``InlineToolRunner`` passed by the chat loop.
// Because LiteRT decodes a *fresh* struct instance for each tool call (via
// `JSONDecoder`), the runner cannot be injected as an instance property —
// it must be held at module scope. Access is serialized by ``LiteRTSessionGate``:
// only one generation (and thus one active runner) runs at a time.
//
// The ``InlineToolRunner`` carries the full permission flow (.always / .ask /
// .never), so all permission policies work for local models, including live UI
// prompts for .ask tools.
//
// ## Adding a new tool
//
// 1. Add a concrete struct conforming to LiteRTLM.Tool below (match the name,
//    description, and @ToolParam fields to the Eigin ToolDefinition exactly).
// 2. Register it in ``GemmaToolBridgeRegistry/all``.

// MARK: - Turn-scoped runner holder

/// Holds the active ``InlineToolRunner`` for the duration of a LiteRT generation
/// turn. Set and cleared by ``GemmaRuntime/stream(_:tools:inlineToolRunner:)``
/// *inside* the session-gate critical section, so the assignment lifetime is
/// exactly the span during which this generation owns the engine. That is what
/// makes the single static safe: a concurrently-created stream (e.g. background
/// title generation) cannot overwrite it while another turn holds the gate.
///
/// LiteRT invokes `run()` from a `Task` spawned inside its native stream
/// callback, where Swift task-local values do not reliably propagate. A
/// module-scoped static survives that C boundary.
enum GemmaToolBridgeRunner {
    nonisolated(unsafe) static var current: InlineToolRunner?
}

// MARK: - Bridge helper

/// Executes a tool call through the turn's active runner and returns a
/// JSON-friendly result for LiteRT to feed back into the conversation.
func runBridgedTool(name: String, arguments: [String: Any]) async throws -> Any {
    guard let runner = GemmaToolBridgeRunner.current else {
        throw BridgedToolError.noActiveRunner
    }
    let argsJSON: String = if let data = try? JSONSerialization.data(withJSONObject: arguments),
                              let str = String(data: data, encoding: .utf8)
    {
        str
    } else {
        "{}"
    }
    let call = ToolCall(
        id: UUID().uuidString,
        type: "function",
        function: ToolCall.FunctionCall(name: name, arguments: argsJSON)
    )
    let result = await runner.run(call)
    return result.content
}

enum BridgedToolError: Error {
    case noActiveRunner
}

// MARK: - Concrete bridge structs

/// `search_knowledge` — bridges to ``SearchKnowledgeTool``.
struct BridgedSearchKnowledge: LiteRTLM.Tool, @unchecked Sendable {
    static let name = "search_knowledge"
    static let description = "Search your knowledge base."

    @ToolParam(description: "Search query.")
    var query: String

    init() {}

    func run() async throws -> Any {
        try await runBridgedTool(name: Self.name, arguments: ["query": query])
    }
}

/// `web_search` — bridges to ``WebSearchTool``.
struct BridgedWebSearch: LiteRTLM.Tool, @unchecked Sendable {
    static let name = "web_search"
    static let description = "Search the web. Returns plain-text results."

    @ToolParam(description: "The search query.")
    var query: String

    init() {}

    func run() async throws -> Any {
        try await runBridgedTool(name: Self.name, arguments: ["query": query])
    }
}

/// `web_fetch` — bridges to ``WebFetchTool``.
struct BridgedWebFetch: LiteRTLM.Tool, @unchecked Sendable {
    static let name = "web_fetch"
    static let description = "Fetch a URL and return its content as plain text."

    @ToolParam(description: "The URL to fetch (http or https).")
    var url: String

    init() {}

    func run() async throws -> Any {
        try await runBridgedTool(name: Self.name, arguments: ["url": url])
    }
}

// MARK: - Sendable box

/// Wraps `[any LiteRTLM.Tool]` so the array can cross Swift 6 task boundaries.
/// All concrete bridge structs are `@unchecked Sendable` value types with no
/// shared mutable state, so this is safe.
final class BridgedToolBox: @unchecked Sendable {
    let tools: [any LiteRTLM.Tool]
    init(_ tools: [any LiteRTLM.Tool]) {
        self.tools = tools
    }
}

// MARK: - Registry

/// Maps tool names to their bridge struct type.
///
/// When ``makeBridgedTools(_:)`` encounters a name not in this registry, it logs
/// a warning and skips the tool. Add an entry here when you add a new concrete
/// bridge struct above.
enum GemmaToolBridgeRegistry {
    static let all: [String: any LiteRTLM.Tool.Type] = [
        BridgedSearchKnowledge.name: BridgedSearchKnowledge.self,
        BridgedWebSearch.name: BridgedWebSearch.self,
        BridgedWebFetch.name: BridgedWebFetch.self,
    ]
}

// MARK: - Factory

extension LocalClient {
    /// Maps incoming ``ToolDefinition``s to concrete bridge instances. Unknown
    /// names are skipped with a warning. Call before creating the conversation.
    static func makeBridgedTools(
        _ definitions: [ToolDefinition]
    ) -> [any LiteRTLM.Tool] {
        var tools: [any LiteRTLM.Tool] = []
        for def in definitions {
            if let type_ = GemmaToolBridgeRegistry.all[def.function.name] {
                let instance = type_.init()
                AppLogger.debug(
                    "Gemma: bridged '\(public: def.function.name)' → \(public: type(of: instance).name)",
                    category: .chat
                )
                tools.append(instance)
            } else {
                AppLogger.warning(
                    "Gemma: no bridge for '\(public: def.function.name)' — skipping",
                    category: .chat
                )
            }
        }
        AppLogger.debug(
            "Gemma: makeBridgedTools returning \(public: tools.count) tools",
            category: .chat
        )
        return tools
    }
}
