import Foundation
import FoundationModels

extension LocalClient {
    static func appleFoundationModelStatus() async -> LocalModelStatus {
        if let reason = FoundationModelClient.unavailableReason {
            return LocalModelStatus(
                id: "apple-foundation-model",
                displayName: Localized.Model.appleFoundationModel,
                state: .unavailable(reason: reason)
            )
        }
        return LocalModelStatus(
            id: "apple-foundation-model",
            displayName: Localized.Model.appleFoundationModel,
            state: .ready
        )
    }

    func appleEventStream(
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        guard FoundationModelClient.isAvailable else {
            throw FoundationModelClientError.notAvailable
        }

        let capturedCalls = CapturedToolCalls()

        return AsyncThrowingStream { continuation in
            Task { @MainActor in
                let inputs = buildSessionInputs(from: messages)
                let nativeTools: [any FoundationModels.Tool] = (tools ?? []).map {
                    BridgedTool(from: $0, capture: capturedCalls)
                }
                let hasTools = !nativeTools.isEmpty
                let session = FoundationModelSessionStore.shared.getOrCreate(
                    chatKey: inputs.chatKey,
                    instructions: inputs.instructions,
                    tools: nativeTools
                )
                let responseStream = session.streamResponse(to: inputs.prompt)
                var lastContent = ""
                do {
                    for try await snapshot in responseStream {
                        let current = snapshot.content
                        if current.count > lastContent.count {
                            let delta = String(current.dropFirst(lastContent.count))
                            if hasTools {
                                lastContent = current
                            } else {
                                continuation.yield(.contentDelta(delta))
                                lastContent = current
                            }
                        }
                    }
                    if hasTools, !lastContent.isEmpty {
                        continuation.yield(.contentDelta(lastContent))
                    }
                    continuation.yield(.finished(.stop))
                    continuation.finish()
                } catch is CancellationError {
                    FoundationModelSessionStore.shared.reset(chatKey: inputs.chatKey)
                    continuation.finish()
                } catch {
                    let calls = capturedCalls.drain()
                    if !calls.isEmpty {
                        for call in calls {
                            continuation.yield(.toolCall(call))
                        }
                        continuation.yield(.finished(.toolCalls))
                        continuation.finish()
                    } else {
                        if let genError = error as? LanguageModelSession.GenerationError {
                            AppLogger.error(
                                "Foundation Model error: \(public: String(describing: genError))",
                                category: .chat
                            )
                        } else {
                            AppLogger.error(
                                "Foundation Model error: \(private: error.localizedDescription) (\(public: String(describing: type(of: error))))",
                                category: .chat
                            )
                        }
                        FoundationModelSessionStore.shared.reset(chatKey: inputs.chatKey)
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }
}
