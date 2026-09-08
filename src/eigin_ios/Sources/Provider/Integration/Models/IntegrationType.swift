import Factory
import Foundation
import SwiftUI

/// Compile-time catalog entry for a connectable integration (analogous to
/// ``BundledSkill``). An ``Integration`` is a connected instance of one of
/// these.
struct IntegrationType: Sendable {
    let id: String
    let displayName: String
    let description: String
    let systemImage: String
    /// Capabilities this integration type can provide. A single integration
    /// (e.g. a Google account) can provide more than one — later capabilities
    /// can be granted on the same connection via incremental OAuth consent.
    let providedCapabilities: Set<Capability>
    /// The category this type belongs to, and the source of truth for
    /// category membership.
    let category: IntegrationCategory
    let authKind: IntegrationAuthKind
    /// For `.oauth` types: which OAuth scopes each capability actually needs,
    /// so the connect flow can tell which capabilities the user really
    /// granted (Google's consent screen lets scopes be denied individually)
    /// rather than assuming every requested capability was approved.
    let requiredScopes: [Capability: Set<String>]
    /// Static ``ToolCapability``s (permission identities), exposed to the
    /// permissions UI even when no instance of this type is connected. Not to
    /// be confused with `providedCapabilities`, which are `Capability` values
    /// (behavior areas, e.g. `.email`) rather than individual tool permissions.
    let toolCapabilities: [ToolCapability]
    /// Builds the tools for one specific granted capability of a connected
    /// instance. Scoped to a single `Capability` (rather than the whole
    /// integration) so a type providing several capabilities — e.g. Google
    /// growing into `.email` and `.calendar` — doesn't leak one capability's
    /// tools into a turn that only asked for another.
    let makeTools: @MainActor (Capability, Integration, ToolContext) -> [any Tool]
    /// Fetches a human-readable label for the connected account (e.g. the
    /// Google address) using the just-issued access token. Defaults to
    /// `displayName` when a type has no better source (or the fetch fails).
    let accountLabel: @Sendable (String) async -> String?
    /// The design-system brand mark, where one ships. Row callers fall back
    /// to the initial (``AppMark``) without it.
    let brandImage: Image?

    init(
        id: String,
        displayName: String,
        description: String,
        systemImage: String,
        // The design-system brand mark, where one ships. Row callers fall
        // back to the initial (``AppMark``) without it.
        brandImage: Image? = nil,
        providedCapabilities: Set<Capability>,
        category: IntegrationCategory,
        authKind: IntegrationAuthKind,
        requiredScopes: [Capability: Set<String>] = [:],
        toolCapabilities: [ToolCapability],
        makeTools: @escaping @MainActor (Capability, Integration, ToolContext) -> [any Tool],
        accountLabel: @escaping @Sendable (String) async -> String? = { _ in nil }
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.systemImage = systemImage
        self.providedCapabilities = providedCapabilities
        self.category = category
        self.authKind = authKind
        self.requiredScopes = requiredScopes
        self.toolCapabilities = toolCapabilities
        self.makeTools = makeTools
        self.accountLabel = accountLabel
        self.brandImage = brandImage
    }

    /// Which of `providedCapabilities` are actually usable given the OAuth
    /// scopes the user granted — a capability only counts as granted when
    /// every scope `requiredScopes` lists for it is present. Capabilities with
    /// no declared scopes (e.g. non-OAuth auth kinds) are granted by default.
    func grantedCapabilities(fromGrantedScopes grantedScopes: Set<String>) -> Set<Capability> {
        providedCapabilities.filter { capability in
            (requiredScopes[capability] ?? []).isSubset(of: grantedScopes)
        }
    }
}

/// Built-in integration types that ship with the app.
enum BundledIntegrationType {
    static let all: [IntegrationType] = [google, microsoft, imap, aula]

    static func type(forID id: String) -> IntegrationType? {
        all.first { $0.id == id }
    }

    static let google = IntegrationType(
        id: "google",
        displayName: "Google",
        description: Localized.Integrations.Google.description,
        systemImage: "envelope.fill",
        brandImage: Iconography.Service.google,
        providedCapabilities: [.email],
        category: .email,
        authKind: .oauth(configFactory: GoogleOAuth.config),
        requiredScopes: [
            .email: [
                "https://www.googleapis.com/auth/gmail.readonly",
                "https://www.googleapis.com/auth/gmail.send",
            ],
        ],
        toolCapabilities: EmailToolCapabilities.all,
        makeTools: { capability, integration, _ in
            switch capability {
            case .email:
                let provider = GmailEmailProvider(
                    integrationID: integration.id,
                    oauthService: Container.shared.integrationOAuthService(),
                    oauthConfig: GoogleOAuth.config(),
                    healthMonitor: IntegrationHealthMonitor.shared
                )
                return EmailToolKit.tools(provider: provider)
            default:
                return []
            }
        },
        accountLabel: { accessToken in await GoogleAccountInfo.email(accessToken: accessToken) }
    )

    static let microsoft = IntegrationType(
        id: "microsoft",
        displayName: "Microsoft",
        description: Localized.Integrations.Microsoft.description,
        systemImage: "envelope.fill",
        brandImage: Iconography.Service.microsoft,
        providedCapabilities: [.email],
        category: .email,
        authKind: .oauth(configFactory: MicrosoftOAuth.config),
        requiredScopes: [
            .email: ["Mail.Read", "Mail.Send"],
        ],
        toolCapabilities: EmailToolCapabilities.all,
        makeTools: { capability, integration, _ in
            switch capability {
            case .email:
                let provider = MicrosoftEmailProvider(
                    integrationID: integration.id,
                    oauthService: Container.shared.integrationOAuthService(),
                    oauthConfig: MicrosoftOAuth.config(),
                    accountAddress: integration.accountLabel,
                    healthMonitor: IntegrationHealthMonitor.shared
                )
                return EmailToolKit.tools(provider: provider)
            default:
                return []
            }
        },
        accountLabel: { accessToken in await MicrosoftAccountInfo.email(accessToken: accessToken) }
    )

    static let imap = IntegrationType(
        id: "imap",
        displayName: Localized.Integrations.Imap.displayName,
        description: Localized.Integrations.Imap.description,
        systemImage: "envelope.fill",
        brandImage: Iconography.Functional.mail,
        providedCapabilities: [.email],
        category: .email,
        authKind: .imap,
        // No OAuth scopes to gate on — a connected IMAP account grants every
        // capability it provides, same as any other non-OAuth auth kind (see
        // `grantedCapabilities(fromGrantedScopes:)`).
        toolCapabilities: EmailToolCapabilities.all,
        makeTools: { capability, integration, _ in
            switch capability {
            case .email:
                let provider = IMAPEmailProvider(
                    integrationID: integration.id,
                    credentialStore: Container.shared.imapCredentialStore(),
                    healthMonitor: IntegrationHealthMonitor.shared
                )
                return EmailToolKit.tools(provider: provider)
            default:
                return []
            }
        }
    )

    static let aula = IntegrationType(
        id: "aula",
        displayName: Localized.Integrations.Aula.displayName,
        description: Localized.Integrations.Aula.description,
        systemImage: "figure.child",
        brandImage: Iconography.Functional.school,
        providedCapabilities: [.aula],
        category: .familyAndSchool,
        authKind: .webSession(configFactory: AulaOAuth.config),
        // No OAuth scopes to gate on — a connected Aula account grants the
        // capability it provides, same as the IMAP non-OAuth kind.
        toolCapabilities: AulaToolCapabilities.all,
        makeTools: { capability, integration, _ in
            switch capability {
            case .aula:
                let provider = DefaultAulaProvider(
                    integrationID: integration.id,
                    credentialStore: Container.shared.aulaCredentialStore(),
                    apiClient: AulaAPIClient(http: URLSessionAulaHTTP()),
                    healthMonitor: IntegrationHealthMonitor.shared
                )
                return AulaToolKit.tools(provider: provider)
            default:
                return []
            }
        }
    )
}
