import UIKit

/// A pre-configured provider template with known name and base URL.
struct ProviderPreset: Identifiable, Hashable {
    enum AuthMethod {
        case apiKey
        case oAuthPKCE
        /// Sign in with ChatGPT — OpenAI subscription OAuth (SIWC).
        case chatGPTSubscription
        /// Sign in with Infercom — PKCE login + RFC 8693 API-token exchange.
        case infercomSignIn
        case none
    }

    enum Region: String {
        case europe
        case usa
        case global

        var emoji: String {
            switch self {
            case .europe: "🇪🇺"
            case .usa: "🇺🇸"
            case .global: "🌐"
            }
        }
    }

    let id: String
    let name: String
    let baseURL: String
    let helpText: String
    let apiKeyURL: String?
    /// The provider's own privacy policy, linked where the user consents to sharing.
    let privacyPolicyURL: String?
    /// SF Symbol name used when no bundled logo exists.
    let systemImage: String?
    let authMethod: AuthMethod
    /// Authorization endpoint for OAuth PKCE providers (e.g. `https://openrouter.ai/auth`).
    let oAuthAuthorizationURL: String?
    /// Token/key exchange endpoint for OAuth PKCE providers.
    let oAuthTokenExchangeURL: String?
    /// Whether this provider requires downloading a model before use.
    let requiresDownload: Bool
    /// Broad geographic region for the provider.
    let region: Region?

    init(
        id: String,
        name: String,
        baseURL: String,
        helpText: String,
        apiKeyURL: String?,
        privacyPolicyURL: String? = nil,
        systemImage: String? = nil,
        authMethod: AuthMethod = .apiKey,
        oAuthAuthorizationURL: String? = nil,
        oAuthTokenExchangeURL: String? = nil,
        requiresDownload: Bool = false,
        region: Region? = nil
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.helpText = helpText
        self.apiKeyURL = apiKeyURL
        self.privacyPolicyURL = privacyPolicyURL
        self.systemImage = systemImage
        self.authMethod = authMethod
        self.oAuthAuthorizationURL = oAuthAuthorizationURL
        self.oAuthTokenExchangeURL = oAuthTokenExchangeURL
        self.requiresDownload = requiresDownload
        self.region = region
    }

    /// Bundled logo from the asset catalog, falling back to nil if not found.
    var logo: UIImage? {
        UIImage(named: "Icons/provider/\(id)")
    }

    static let all: [ProviderPreset] = [
        ProviderPreset(
            id: "eigin",
            name: "Eigin",
            baseURL: "eigin-relay://",
            helpText: Localized.Provider.Eigin.rowSubtitle,
            apiKeyURL: nil,
            systemImage: "sparkles",
            authMethod: .none,
            region: .europe
        ),
        ProviderPreset(
            id: "local",
            name: Localized.Provider.onDevice,
            baseURL: "local://",
            helpText: Localized.Onboarding.LocalModel.description,
            apiKeyURL: nil,
            systemImage: "cpu.fill",
            authMethod: .none,
            region: nil
        ),
        ProviderPreset(
            id: "openai-chatgpt",
            name: "ChatGPT",
            baseURL: "openai-chatgpt://",
            helpText: Localized.Provider.Setup.Chatgpt.instruction,
            apiKeyURL: nil,
            privacyPolicyURL: "https://openai.com/policies/privacy-policy/",
            authMethod: .chatGPTSubscription,
            region: .usa
        ),
        ProviderPreset(
            id: "openai",
            name: "OpenAI",
            baseURL: "https://api.openai.com/v1",
            helpText: Localized.Provider.Setup.Openai.instruction,
            apiKeyURL: "https://platform.openai.com/api-keys",
            privacyPolicyURL: "https://openai.com/policies/privacy-policy/",
            region: .usa
        ),
        ProviderPreset(
            id: "anthropic",
            name: "Anthropic",
            baseURL: "https://api.anthropic.com/v1",
            helpText: Localized.Provider.Setup.Anthropic.instruction,
            apiKeyURL: "https://platform.claude.com/settings/keys",
            privacyPolicyURL: "https://www.anthropic.com/legal/privacy",
            region: .usa
        ),
        ProviderPreset(
            id: "google",
            name: "Google",
            baseURL: "https://generativelanguage.googleapis.com/v1beta/openai/",
            helpText: Localized.Provider.Setup.Google.instruction,
            apiKeyURL: "https://aistudio.google.com/api-keys",
            privacyPolicyURL: "https://policies.google.com/privacy",
            region: .usa
        ),
        ProviderPreset(
            id: "mistral",
            name: "Mistral",
            baseURL: "https://api.mistral.ai/v1",
            helpText: Localized.Provider.Setup.Mistral.instruction,
            apiKeyURL: "https://console.mistral.ai/api-keys",
            privacyPolicyURL: "https://legal.mistral.ai/terms/privacy-policy",
            region: .europe
        ),
        ProviderPreset(
            id: "eurouter",
            name: "EUrouter",
            baseURL: "https://api.eurouter.ai/api/v1",
            helpText: Localized.Provider.Setup.Eurouter.instruction,
            apiKeyURL: "https://www.eurouter.ai/dashboard",
            privacyPolicyURL: "https://www.eurouter.ai/privacy",
            authMethod: .oAuthPKCE,
            oAuthAuthorizationURL: "https://api.eurouter.ai/api/v1/auth",
            oAuthTokenExchangeURL: "https://api.eurouter.ai/api/v1/auth/keys",
            region: .europe
        ),
        ProviderPreset(
            id: "openrouter",
            name: "OpenRouter",
            baseURL: "https://openrouter.ai/api/v1",
            helpText: Localized.Provider.Setup.Openrouter.instruction,
            apiKeyURL: "https://openrouter.ai/settings/credits",
            privacyPolicyURL: "https://openrouter.ai/privacy",
            authMethod: .oAuthPKCE,
            oAuthAuthorizationURL: "https://openrouter.ai/auth",
            oAuthTokenExchangeURL: "https://openrouter.ai/api/v1/auth/keys",
            region: .global
        ),
        ProviderPreset(
            id: "berget",
            name: "Berget AI",
            baseURL: "https://api.berget.ai/v1",
            helpText: Localized.Provider.Setup.Berget.instruction,
            apiKeyURL: "https://console.berget.ai/api-keys",
            privacyPolicyURL: "https://berget.ai/privacy",
            region: .europe
        ),
        ProviderPreset(
            id: "infercom",
            name: "Infercom",
            baseURL: "https://api.infercom.ai/v1",
            helpText: Localized.Provider.Setup.Infercom.instruction,
            apiKeyURL: "https://cloud.infercom.ai/apis",
            privacyPolicyURL: "https://infercom.ai/privacypolicy/",
            authMethod: .infercomSignIn,
            region: .europe
        ),
        ProviderPreset(
            id: "corti",
            name: "Corti",
            baseURL: "https://ai.eu.corti.app/v1",
            helpText: Localized.Provider.Setup.Corti.instruction,
            apiKeyURL: "https://console.corti.app",
            privacyPolicyURL: "https://www.corti.ai/legal/privacy-policy",
            region: .europe
        ),
    ]
}
