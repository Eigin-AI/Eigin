import UIKit

/// A pre-configured provider template with known name and base URL.
struct ProviderPreset: Identifiable, Hashable {
    enum AuthMethod {
        case apiKey
        case oAuthPKCE
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

    /// Whether this provider runs on-device (no API key, no network).
    static func isLocal(_ baseURL: String) -> Bool {
        baseURL.hasPrefix("local://")
    }

    static let all: [ProviderPreset] = [
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
            id: "openai",
            name: "OpenAI",
            baseURL: "https://api.openai.com/v1",
            helpText: Localized.Provider.Setup.Openai.instruction,
            apiKeyURL: "https://platform.openai.com/api-keys",
            region: .usa
        ),
        ProviderPreset(
            id: "anthropic",
            name: "Anthropic",
            baseURL: "https://api.anthropic.com/v1",
            helpText: Localized.Provider.Setup.Anthropic.instruction,
            apiKeyURL: "https://platform.claude.com/settings/keys",
            region: .usa
        ),
        ProviderPreset(
            id: "google",
            name: "Google",
            baseURL: "https://generativelanguage.googleapis.com/v1beta/openai/",
            helpText: Localized.Provider.Setup.Google.instruction,
            apiKeyURL: "https://aistudio.google.com/api-keys",
            region: .usa
        ),
        ProviderPreset(
            id: "mistral",
            name: "Mistral",
            baseURL: "https://api.mistral.ai/v1",
            helpText: Localized.Provider.Setup.Mistral.instruction,
            apiKeyURL: "https://console.mistral.ai/api-keys",
            region: .europe
        ),
        ProviderPreset(
            id: "eurouter",
            name: "EUrouter",
            baseURL: "https://api.eurouter.ai/api/v1",
            helpText: Localized.Provider.Setup.Eurouter.instruction,
            apiKeyURL: "https://www.eurouter.ai/dashboard",
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
            authMethod: .oAuthPKCE,
            oAuthAuthorizationURL: "https://openrouter.ai/auth",
            oAuthTokenExchangeURL: "https://openrouter.ai/api/v1/auth/keys",
            region: .global
        ),
        ProviderPreset(
            id: "scaleway",
            name: "Scaleway",
            baseURL: "https://api.scaleway.ai/v1",
            helpText: Localized.Provider.Setup.Scaleway.instruction,
            apiKeyURL: "https://console.scaleway.com/iam/api-keys",
            region: .europe
        ),
        ProviderPreset(
            id: "ovhcloud",
            name: "OVHcloud",
            baseURL: "https://oai.endpoints.kepler.ai.cloud.ovh.net/v1",
            helpText: Localized.Provider.Setup.Ovh.instruction,
            apiKeyURL: "https://endpoints.ai.cloud.ovh.net/",
            region: .europe
        ),
    ]
}
