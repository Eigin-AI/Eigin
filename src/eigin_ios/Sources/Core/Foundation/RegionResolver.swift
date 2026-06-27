import Foundation

/// A region we can tailor seasonal awareness to.
///
/// Deliberately coarse: we only resolve regions we have a seasonal calendar
/// for. Denmark is the only entry today; add cases as other regions come
/// online.
enum Region {
    case denmark

    /// Maps an ISO 3166-1 country code (e.g. `"DK"`) to a known region.
    init?(countryCode: String) {
        switch countryCode.uppercased() {
        case "DK": self = .denmark
        default: return nil
        }
    }

    /// Maps an IANA timezone identifier (e.g. `"Europe/Copenhagen"`) to a known
    /// region. Used only as a fallback when the device exposes no region code.
    init?(timeZoneIdentifier: String) {
        switch timeZoneIdentifier {
        case "Europe/Copenhagen": self = .denmark
        default: return nil
        }
    }
}

/// Deduces the user's region from ambient, non-invasive signals — no location
/// permission prompt.
///
/// The device region setting (`Locale.current.region`) is the primary signal:
/// it's independent of language, so a Danish user running an English-language
/// phone still resolves to Denmark. The timezone is a fallback for the rare
/// case where no region code is exposed. If neither lands on a region we know,
/// `resolve()` returns `nil` and callers stay silent rather than guessing.
struct RegionResolver {
    /// The device's ISO region code, or `nil`. Injectable for tests.
    var regionCode: @Sendable () -> String?
    /// The device's IANA timezone identifier. Injectable for tests.
    var timeZoneIdentifier: @Sendable () -> String

    /// Reads the live device signals.
    static let live = RegionResolver(
        regionCode: { Locale.current.region?.identifier },
        timeZoneIdentifier: { TimeZone.current.identifier }
    )

    /// Resolves a known region, or `nil` when the signals are inconclusive.
    func resolve() -> Region? {
        if let code = regionCode(), let region = Region(countryCode: code) {
            return region
        }
        return Region(timeZoneIdentifier: timeZoneIdentifier())
    }
}
