import Foundation

/// Microsoft's known OAuth endpoints and scopes for the Graph email
/// capability, scoped to **personal** accounts (Hotmail, outlook.com,
/// live.dk) via the `/consumers` authority — work/school accounts aren't
/// supported.
///
/// Uses a custom-scheme redirect (`msauth.<bundle-id>://auth`), the
/// convention for Microsoft's "Mobile and desktop applications" public-client
/// platform: no client secret, and `ASWebAuthenticationSession` intercepts
/// the scheme directly with no `Info.plist` URL-type registration needed.
/// Unlike Google, this redirect URI is one Eigin controls rather than one
/// Microsoft fixes — but it must still be registered in the Azure app
/// registration for the flow to complete.
enum MicrosoftOAuth {
    static func config() -> PKCEOAuthConfig {
        PKCEOAuthConfig(
            authorizationEndpoint: URL(
                string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/authorize"
            )!,
            tokenEndpoint: URL(
                string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/token"
            )!,
            clientID: AppKeys.microsoftOAuthClientID,
            scopes: ["Mail.Read", "Mail.Send", "offline_access", "User.Read"],
            redirectURI: redirectURI(bundleID: AppKeys.bundleIdentifier)
        )
    }

    /// Microsoft's native-app redirect convention: `msauth.<bundle-id>://auth`.
    static func redirectURI(bundleID: String) -> String {
        "msauth.\(bundleID)://auth"
    }
}
