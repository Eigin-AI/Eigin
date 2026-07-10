import Foundation

/// How an ``IntegrationType`` authenticates a connection.
///
/// Cases are added when a real need lands rather than speculatively; e.g.
/// `.appKey` arrives with the Rejseplanen integration.
enum IntegrationAuthKind {
    /// PKCE authorization-code flow against a pre-configured (non-discovered)
    /// endpoint pair. `configFactory` builds the flow config lazily so secrets
    /// (client ID) aren't read until a connection is actually attempted.
    case oauth(configFactory: @Sendable () -> PKCEOAuthConfig)

    /// Manually entered server credentials (host/port/username/password for
    /// both IMAP and SMTP), verified by connecting on add rather than via a
    /// redirect-based flow. No associated config — unlike OAuth, there's no
    /// pre-configured endpoint pair to build lazily; the connect flow collects
    /// settings from the user and hands them to ``IMAPConnectionVerifier``.
    case imap
}
