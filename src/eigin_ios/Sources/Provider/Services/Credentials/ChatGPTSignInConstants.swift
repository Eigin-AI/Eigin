import Foundation

enum ChatGPTSignInConstants {
    static let authorizeURL = URL(string: "https://auth.openai.com/api/accounts/authorize")!
    static let tokenURL = URL(string: "https://auth.openai.com/api/accounts/oauth/token")!
    static let jwksURL = URL(string: "https://auth.openai.com/.well-known/jwks.json")!
    static let issuer = "https://auth.openai.com"
    static let resource = "https://api.openai.com/v1"
    static let scopes = [
        "openid", "profile", "email", "resource.invoke",
        "chatgpt.tokens.use.direct", "offline_access",
    ]

    /// The scope that actually authorizes ChatGPT plan usage; its absence
    /// means the user declined token sharing (identity-only result).
    static let planUsageScope = "chatgpt.tokens.use.direct"
    static let registrationClientID = "dynamic_agent_client"
    static let agentNameHint = "Eigin"
    static let callbackPath = "/auth/callback"
    /// How long the loopback listener stays open waiting for the browser.
    static let listenTimeout: TimeInterval = 600
}
