@testable import Eigin
import Foundation
import Testing

// MARK: - Provider Configuration

struct ProviderTestConfig: CustomStringConvertible {
    let name: String
    let envVar: String
    let baseURL: String
    let model: String
    let supportsTool: Bool
    var description: String {
        "\(name)/\(model)"
    }

    static let all: [ProviderTestConfig] = [
        ProviderTestConfig(
            name: "OpenAI",
            envVar: "OPENAI_API_KEY",
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4.1",
            supportsTool: true
        ),
        ProviderTestConfig(
            name: "Anthropic",
            envVar: "ANTHROPIC_API_KEY",
            baseURL: "https://api.anthropic.com/v1/",
            model: "claude-sonnet-4-20250514",
            supportsTool: true
        ),
        ProviderTestConfig(
            name: "Google",
            envVar: "GOOGLE_API_KEY",
            baseURL: "https://generativelanguage.googleapis.com/v1beta/openai/",
            model: "gemini-2.5-flash",
            supportsTool: true
        ),
        ProviderTestConfig(
            name: "Mistral",
            envVar: "MISTRAL_API_KEY",
            baseURL: "https://api.mistral.ai/v1",
            model: "mistral-large-latest",
            supportsTool: true
        ),
        ProviderTestConfig(
            name: "Groq",
            envVar: "GROQ_API_KEY",
            baseURL: "https://api.groq.com/openai/v1",
            model: "llama-3.3-70b-versatile",
            supportsTool: true
        ),
        ProviderTestConfig(
            name: "OpenRouter",
            envVar: "OPENROUTER_API_KEY",
            baseURL: "https://openrouter.ai/api/v1",
            model: "openai/gpt-4.1",
            supportsTool: true
        ),
    ]
}

// MARK: - Test Scenarios

enum TestScenarios {
    static let simpleCompletion: [ChatMessage] = [
        ChatMessage(role: "user", content: "Say hello. Reply in one word."),
    ]

    static let withSystemPrompt: [ChatMessage] = [
        ChatMessage(role: "system", content: "You are a helpful assistant. Keep replies brief."),
        ChatMessage(role: "user", content: "Hi there."),
    ]

    static let multiTurn: [ChatMessage] = [
        ChatMessage(role: "user", content: "My name is Zenith."),
        ChatMessage(role: "assistant", content: "Nice to meet you, Zenith!"),
        ChatMessage(role: "user", content: "What was my name? One word."),
    ]

    static let toolCallingMessages: [ChatMessage] = [
        ChatMessage(
            role: "system",
            content: "When asked about weather, always use the get_weather tool."
        ),
        ChatMessage(role: "user", content: "What's the weather in Paris?"),
    ]

    static let weatherTool = ToolDefinition(
        name: "get_weather",
        description: "Get the current weather for a location.",
        parameters: JSONSchema(
            type: "object",
            properties: [
                "location": JSONSchema.Property(type: "string", description: "City name"),
            ],
            required: ["location"]
        )
    )

    /// Builds the full tool round-trip messages: user question → assistant tool call → tool result.
    static func toolRoundTripMessages(
        toolCall: ToolCall,
        providerMetadata: [String: String]?
    ) -> [ChatMessage] {
        var messages = toolCallingMessages

        // Assistant message with the tool call
        messages.append(ChatMessage(
            role: "assistant",
            toolCalls: [toolCall],
            providerMetadata: providerMetadata
        ))

        // Tool result message
        messages.append(ChatMessage(
            role: "tool",
            content: "{\"temperature\": \"18°C\", \"condition\": \"Partly cloudy\"}",
            toolCallID: toolCall.id
        ))

        return messages
    }
}

// MARK: - Env File Loader

/// Reads key=value pairs from a dotenv file, supporting `export` prefixes and `#` comments.
private func loadDotEnv(at url: URL) -> [String: String] {
    guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
    var vars: [String: String] = [:]
    for line in contents.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
        let stripped = trimmed.hasPrefix("export ") ? String(trimmed.dropFirst(7)) : trimmed
        let parts = stripped.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else { continue }
        let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
        var value = String(parts[1]).trimmingCharacters(in: .whitespaces)
        // Strip surrounding quotes
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
            (value.hasPrefix("'") && value.hasSuffix("'"))
        {
            value = String(value.dropFirst().dropLast())
        }
        vars[key] = value
    }
    return vars
}

/// Resolves the repo root from this source file's compile-time path.
/// Layout: <repo>/src/eigin_ios/Tests/ProviderIntegrationTests.swift
private let repoRoot: URL = .init(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // Tests/
    .deletingLastPathComponent() // eigin_ios/
    .deletingLastPathComponent() // src/
    .deletingLastPathComponent() // repo root

/// Merged environment: .env file values, overridden by process environment (for CI).
private let resolvedEnv: [String: String] = {
    let envURL = repoRoot.appendingPathComponent(".env")
    let dotEnv = loadDotEnv(at: envURL)
    if dotEnv.isEmpty {
        print("[IntegrationTests] WARNING: Could not load .env from \(envURL.path)")
    } else {
        let apiKeys = dotEnv.keys.filter { $0.hasSuffix("_API_KEY") }.sorted()
        print(
            "[IntegrationTests] Loaded .env from \(envURL.path) — API keys found: \(apiKeys.isEmpty ? "none" : apiKeys.joined(separator: ", "))"
        )
    }
    var env = dotEnv
    // Process env takes precedence (useful in CI where env vars are set directly)
    for (key, value) in ProcessInfo.processInfo.environment {
        env[key] = value
    }
    return env
}()

// MARK: - Test Suite

@Suite("Provider Integration Tests", .serialized, .tags(.integration), .timeLimit(.minutes(2)))
struct ProviderIntegrationTests {
    /// Pause between API calls to avoid rate limits.
    private static let requestDelay: UInt64 = 1_000_000_000 // 1 second

    /// Returns a live client for the provider, or nil if the API key is missing.
    /// Adds a delay before each call to stay under provider rate limits.
    private func makeClient(for config: ProviderTestConfig) async -> OpenAICompatibleClient? {
        guard let apiKey = resolvedEnv[config.envVar], !apiKey.isEmpty else {
            print("[IntegrationTests] SKIP \(config.name) — no \(config.envVar)")
            return nil
        }
        print(
            "[IntegrationTests] RUN  \(config.name) — \(config.envVar) found (\(apiKey.prefix(8))...)"
        )
        try? await Task.sleep(nanoseconds: Self.requestDelay)
        return OpenAICompatibleClient(baseURL: config.baseURL, apiToken: apiKey)
    }

    // MARK: - fetchModels

    @Test("fetchModels", arguments: ProviderTestConfig.all)
    func fetchModels(config: ProviderTestConfig) async throws {
        guard let client = await makeClient(for: config) else { return }

        let models = try await client.fetchModels()
        #expect(!models.isEmpty, "Expected at least one model from \(config.name)")
    }

    // MARK: - simpleCompletion

    @Test("simpleCompletion", arguments: ProviderTestConfig.all)
    func simpleCompletion(config: ProviderTestConfig) async throws {
        guard let client = await makeClient(for: config) else { return }

        let events = try await collectEvents(
            from: client.chatCompletionEventStream(
                messages: TestScenarios.simpleCompletion,
                model: config.model
            )
        )

        #expect(
            events.contains(where: { if case .contentDelta = $0 { return true }; return false }),
            "Expected at least one contentDelta from \(config.name)"
        )
        #expect(
            events.contains(where: { if case .finished = $0 { return true }; return false }),
            "Expected a finished event from \(config.name)"
        )
    }

    // MARK: - withSystemPrompt

    @Test("withSystemPrompt", arguments: ProviderTestConfig.all)
    func withSystemPrompt(config: ProviderTestConfig) async throws {
        guard let client = await makeClient(for: config) else { return }

        let events = try await collectEvents(
            from: client.chatCompletionEventStream(
                messages: TestScenarios.withSystemPrompt,
                model: config.model
            )
        )

        #expect(
            events.contains(where: { if case .contentDelta = $0 { return true }; return false }),
            "Expected at least one contentDelta from \(config.name)"
        )
        #expect(
            events.contains(where: { if case .finished = $0 { return true }; return false }),
            "Expected a finished event from \(config.name)"
        )
    }

    // MARK: - multiTurn

    @Test("multiTurn", arguments: ProviderTestConfig.all)
    func multiTurn(config: ProviderTestConfig) async throws {
        guard let client = await makeClient(for: config) else { return }

        let events = try await collectEvents(
            from: client.chatCompletionEventStream(
                messages: TestScenarios.multiTurn,
                model: config.model
            )
        )

        #expect(
            events.contains(where: { if case .contentDelta = $0 { return true }; return false }),
            "Expected at least one contentDelta from \(config.name)"
        )
        #expect(
            events.contains(where: { if case .finished = $0 { return true }; return false }),
            "Expected a finished event from \(config.name)"
        )
    }

    // MARK: - toolCalling

    @Test("toolCalling", arguments: ProviderTestConfig.all)
    func toolCalling(config: ProviderTestConfig) async throws {
        guard config.supportsTool else { return }
        guard let client = await makeClient(for: config) else { return }

        let events = try await collectEvents(
            from: client.chatCompletionEventStream(
                messages: TestScenarios.toolCallingMessages,
                model: config.model,
                tools: [TestScenarios.weatherTool]
            )
        )

        let toolCalls = events.compactMap { event -> ToolCall? in
            if case .toolCall(let tc) = event { return tc }
            return nil
        }

        #expect(!toolCalls.isEmpty, "Expected at least one toolCall event from \(config.name)")

        if let firstCall = toolCalls.first {
            #expect(!firstCall.id.isEmpty, "Tool call ID should not be empty")
            #expect(firstCall.function.name == "get_weather", "Expected get_weather tool call")
            // Verify arguments is parseable JSON
            let argsData = Data(firstCall.function.arguments.utf8)
            #expect(throws: Never.self) {
                _ = try JSONSerialization.jsonObject(with: argsData)
            }
        }

        #expect(events.contains(where: {
            if case .finished(.toolCalls) = $0 { return true }
            return false
        }), "Expected finished(.toolCalls) from \(config.name)")
    }

    // MARK: - toolRoundTrip

    @Test("toolRoundTrip", arguments: ProviderTestConfig.all)
    func toolRoundTrip(config: ProviderTestConfig) async throws {
        guard config.supportsTool else { return }
        guard let client = await makeClient(for: config) else { return }

        // Step 1: Get the tool call from the provider
        let firstEvents = try await collectEvents(
            from: client.chatCompletionEventStream(
                messages: TestScenarios.toolCallingMessages,
                model: config.model,
                tools: [TestScenarios.weatherTool]
            )
        )

        guard let toolCall = firstEvents.compactMap({ event -> ToolCall? in
            if case .toolCall(let tc) = event { return tc }
            return nil
        }).first else {
            Issue.record("No tool call received from \(config.name) — cannot test round-trip")
            return
        }

        // Capture provider metadata (e.g. Gemini thought_signature) if present
        let providerMetadata = firstEvents.compactMap { event -> [String: String]? in
            if case .providerMetadata(let meta) = event { return meta }
            return nil
        }.first

        // Step 2: Send the tool result back and verify the response
        let roundTripMessages = TestScenarios.toolRoundTripMessages(
            toolCall: toolCall,
            providerMetadata: providerMetadata
        )

        let secondEvents = try await collectEvents(
            from: client.chatCompletionEventStream(
                messages: roundTripMessages,
                model: config.model,
                tools: [TestScenarios.weatherTool]
            )
        )

        #expect(
            secondEvents
                .contains(where: { if case .contentDelta = $0 { return true }; return false }),
            "Expected content deltas in round-trip response from \(config.name)"
        )
        #expect(
            secondEvents.contains(where: { if case .finished = $0 { return true }; return false }),
            "Expected a finished event in round-trip response from \(config.name)"
        )
    }

    // MARK: - Helpers

    /// Drains an async throwing stream into an array.
    private func collectEvents(from stream: AsyncThrowingStream<
        ChatStreamEvent,
        Error
    >) async throws
        -> [ChatStreamEvent]
    {
        var events: [ChatStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }
}

// MARK: - Custom Tag

extension Tag {
    @Tag static var integration: Self
}
