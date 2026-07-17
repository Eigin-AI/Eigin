import Foundation

/// Everything needed to make authenticated calls to Aula's unofficial JSON
/// API after a successful login, persisted as a single JSON blob in the
/// Keychain.
struct AulaSession: Codable, Equatable, Sendable {
    /// OAuth access token from the PKCE exchange, when the login minted one.
    var accessToken: String?

    /// OAuth refresh token, when Aula issued one.
    var refreshToken: String?

    /// Absolute expiry of `accessToken`, when known.
    var expiresAt: Date?

    /// Session cookies captured at login (name → value), including
    /// `Csrfp-Token` and the PHP session cookie.
    var cookies: [String: String]

    /// The API version last known to work, e.g. 21. Bumped on HTTP 410.
    var apiVersion: Int

    /// The logged-in guardian's children, captured at connect time.
    var children: [AulaChild]

    /// The guardian's own `institutionProfile.id`(s), parallel to each
    /// ``AulaChild/institutionProfileID``. `nil` for sessions connected
    /// before this existed.
    var guardianInstitutionProfileIDs: [Int]? = nil

    /// The API version the live Aula web app currently uses (observed in the
    /// browser); the starting point the provider probes from before any 410
    /// bump. Starting here rather than lower avoids a needless bump loop and
    /// sidesteps endpoints that reject an older version outright.
    static let initialAPIVersion = 24

    /// The value of the CSRF cookie Aula echoes back in the `csrfp-token`
    /// request header, if present.
    var csrfToken: String? {
        cookies["Csrfp-Token"]
    }
}
