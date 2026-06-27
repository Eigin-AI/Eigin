import Foundation

/// Primes the agent with seasonal awareness — what time of year it is for the
/// user, and a warm nudge to be useful around the season's holidays and breaks.
///
/// The hint is region-aware and only fires when we can deduce a known region
/// from ambient signals (see ``RegionResolver``) and a seasonal moment is
/// active on the current date. Otherwise it stays silent: a region-less "it's
/// summer" risks guessing wrong about hemisphere and holidays.
///
/// Stateless. Skipped in compact mode where every token counts.
@MainActor
final class SeasonalInfoSource: SystemHintSource {
    let title = "Seasonal"

    /// Clock injected for testability. Defaults to `Date.init`.
    private let now: @Sendable () -> Date
    /// Region deduction, injectable for tests. Defaults to live device signals.
    private let regionResolver: RegionResolver

    init(
        now: @escaping @Sendable () -> Date = Date.init,
        regionResolver: RegionResolver = .live
    ) {
        self.now = now
        self.regionResolver = regionResolver
    }

    func render(_ input: SystemHintInput) async -> String? {
        guard !input.isSmallContext else { return nil }
        guard let region = regionResolver.resolve() else { return nil }
        guard let moment = SeasonalCalendar.activeMoment(region: region, on: now())
        else { return nil }
        return moment.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
