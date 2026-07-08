import Foundation

/// How an ``IntegrationType`` authenticates a connection.
///
/// Only `.oauth` exists today (on-device PKCE, public client — no client
/// secret, no relay infrastructure). Cases are added when a real need lands
/// rather than speculatively; e.g. `.appKey` arrives with the Rejseplanen
/// integration.
enum IntegrationAuthKind {
    /// PKCE authorization-code flow against a pre-configured (non-discovered)
    /// endpoint pair. `configFactory` builds the flow config lazily so secrets
    /// (client ID) aren't read until a connection is actually attempted.
    case oauth(configFactory: @Sendable () -> PKCEOAuthConfig)
}
