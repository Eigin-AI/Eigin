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

    /// PKCE flow that runs the login in an interactive in-app `WKWebView`
    /// rather than `ASWebAuthenticationSession`, for a provider whose login
    /// flow needs cookies or can't complete in a system browser sheet. The
    /// PKCE mechanics and token exchange are still the shared
    /// ``PKCEOAuthFlow``. Like `.oauth`, the config is built lazily so the
    /// client id isn't read until a connection is attempted.
    case webSession(configFactory: @Sendable () -> PKCEOAuthConfig)

    /// A permission iOS holds rather than an account: Apple Health, Calendar,
    /// Reminders, Location. Connecting says what Eigin will touch, then asks
    /// iOS; there are no credentials to store. These connect through
    /// ``ConnectPlatformSheet`` and open ``PlatformIntegrationScreen``, never
    /// the account flows.
    case platform(PlatformAccessSource)

    /// The iOS permission source, for a platform integration.
    var platform: PlatformAccessSource? {
        if case .platform(let source) = self { return source }
        return nil
    }
}
