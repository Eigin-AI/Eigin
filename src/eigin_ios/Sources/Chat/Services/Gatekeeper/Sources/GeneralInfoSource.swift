import Foundation

/// Surfaces ambient contextual information that doesn't belong to any single
/// concept — currently the local date and time, the device timezone, the
/// current AI provider, and the active model.
///
/// Stateless. The agent can still call the `get_time_and_place` tool when it
/// needs location or an up-to-the-second reading, but having the time in the
/// hint block means simple temporal reasoning ("is it morning?", "what day is
/// it?") works without a tool round-trip.
///
/// Skipped in compact mode where every token counts.
@MainActor
final class GeneralInfoSource: SystemHintSource {
    let title = "General info"

    /// Clock injected for testability. Defaults to `Date.init`.
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    func render(_ input: SystemHintInput) async -> String? {
        // Small context: just time + model awareness
        if input.isSmallContext {
            let timeString = LocalDateFormatter.string(from: now())
            let timeZone = TimeZone.current.abbreviation() ?? "UTC"
            let modelName = KnownModelCatalog.lookup(input.modelID)?.displayName ?? input.modelID
            return "\(timeString) (\(timeZone)). Running locally on \(modelName). The user can add cloud AI providers for more capability."
        }

        guard !input.isSmallContext else { return nil }

        let timeString = LocalDateFormatter.string(from: now())
        let timeZone = TimeZone.current.abbreviation() ?? "UTC"

        let modelName = KnownModelCatalog.lookup(input.modelID)?.displayName ?? input.modelID

        let providerLine: String = if input.provider.isLocal {
            "\(input.provider.name) (on-device)"
        } else {
            input.provider.name
        }

        return """
        Local time: \(timeString) (\(timeZone))
        Provider: \(providerLine)
        Model: \(modelName)
        """
    }
}
