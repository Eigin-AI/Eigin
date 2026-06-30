import Foundation

/// Priority of an on-device generation request.
///
/// The local LiteRT engine supports only one active session, so generation is
/// serialized. An `.interactive` request (a foreground chat send) preempts a
/// running `.background` request (compaction, title generation) so the user is
/// never blocked behind best-effort work.
enum LocalGenerationPriority: Sendable {
    case interactive
    case background
}

/// Carries the current generation priority down to the local client.
///
/// The value is propagated via task-local inheritance, so a call site can mark a
/// whole generation as background without threading a parameter through the
/// `LLMClient` protocol:
///
/// ```swift
/// await LocalGeneration.$priority.withValue(.background) {
///     // stream created here inherits .background
/// }
/// ```
enum LocalGeneration {
    @TaskLocal static var priority: LocalGenerationPriority = .interactive
}
