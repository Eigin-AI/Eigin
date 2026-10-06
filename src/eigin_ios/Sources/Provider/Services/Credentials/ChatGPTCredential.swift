import Foundation

/// The full ChatGPT sign-in credential, saved once the sign-in flow has
/// validated everything (ID token, issued client ID, granted scopes).
struct ChatGPTCredential: Equatable, Sendable {
    /// The ID OpenSIWC issued at registration (`oaiapp_…`) — never
    /// `dynamic_agent_client`, which is only the first-time entrypoint.
    var clientID: String
    var accessToken: String
    var refreshToken: String
    /// Retained so a later sign-in can pass `id_token_hint` and skip the
    /// account selector. May be expired; it identifies, not authenticates.
    var idToken: String
    var expiry: Date
    var scopes: [String]
}
