import Factory
import SwiftData
import SwiftUI
import WebKit

/// Sheet for connecting Aula: runs the real UniLogin/MitID login in an
/// interactive `WKWebView` (see ``AulaLoginWebView``), then verifies the
/// resulting session and saves it as an integration. Presented from
/// ``AddIntegration`` when the user picks the Aula type. See
/// `docs/src/integrations/aula.md` for why Aula needs a custom web view
/// instead of `ASWebAuthenticationSession`.
struct AddAulaAccount: View {
    /// Invoked after the integration is saved, so the presenting sheet can
    /// dismiss itself too.
    var onConnected: () -> Void = {}

    let config: PKCEOAuthConfig

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colors) private var colors
    @Environment(\.scenePhase) private var scenePhase
    @Injected(\.aulaCredentialStore) private var credentialStore

    /// PKCE material for this login attempt, generated once and kept stable
    /// across redraws.
    @State private var pkce = LoginPKCE()
    @State private var phase: Phase = .loggingIn
    /// Bumped on foreground to nudge ``AulaLoginWebView`` to redraw — see the
    /// WKWebView backgrounding quirk in `docs/src/integrations/aula.md`.
    @State private var wakeToken = 0

    var body: some View {
        VStack(spacing: 0) {
            AppNavigationHeader(
                title: Localized.Integrations.Aula.displayName,
                leading: {
                    AppActionButton(
                        icon: Image(systemName: "xmark"),
                        variant: .open,
                        size: .medium,
                        action: { dismiss() }
                    )
                }
            )

            content
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, phase == .loggingIn else { return }
            wakeToken += 1
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loggingIn:
            if let authorizationURL {
                AulaLoginWebView(
                    authorizationURL: authorizationURL,
                    expectedState: pkce.state,
                    redirectHost: URL(string: config.redirectURI)?
                        .host ?? AulaOAuth.redirectHost,
                    onResult: handleCallback,
                    onFormIntercepted: handleFormIntercepted,
                    onError: failWithMessage,
                    wakeToken: wakeToken
                )
            } else {
                errorCard(Localized.Errors.Aula.unexpectedResponse)
            }
        case .verifying:
            VStack(spacing: Spacing.n8) {
                ProgressView()
                Text(Localized.Auth.waiting)
                    .typography(Typography.tag)
                    .foregroundStyle(colors.text.standard.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message):
            ScrollView { errorCard(message).padding(Spacing.n16) }
        }
    }

    private func errorCard(_ message: String) -> some View {
        AppCardSurface {
            VStack(alignment: .leading, spacing: Spacing.n8) {
                Label(Localized.Errors.Connection.title, systemImage: "exclamationmark.triangle")
                    .typography(Typography.titleXS)
                    .foregroundStyle(colors.text.standard.error)
                Text(message)
                    .typography(Typography.tag)
                    .foregroundStyle(colors.text.standard.muted)
            }
        }
    }

    private var authorizationURL: URL? {
        try? PKCEOAuthFlow.buildAuthorizationURL(
            config: config,
            codeChallenge: pkce.challenge,
            state: pkce.state
        )
    }

    /// Direct path: the web view actually caught the callback redirect (rare,
    /// only when the Aula app isn't installed to steal the universal link).
    private func handleCallback(callbackURL: URL, cookies: [HTTPCookie]) {
        phase = .verifying
        Task {
            do {
                let code = try PKCEOAuthFlow.validateCallback(
                    callbackURL,
                    expectedState: pkce.state
                )
                let tokens = try await PKCEOAuthFlow.exchangeCode(
                    code: code,
                    codeVerifier: pkce.verifier,
                    config: config
                )
                // This direct path doesn't run the intercept script, so no
                // user agent is captured — a later silent re-authorize for
                // this session falls back to the walker's own default.
                try await finish(tokens: tokens, cookies: cookies, userAgent: nil)
            } catch {
                fail(error)
            }
        }
    }

    /// Recovery path: finishes the SAML chain headlessly via
    /// ``AulaFormWalker`` once a pending form is intercepted, so the callback
    /// navigation never reaches the installed Aula app — see
    /// `docs/src/integrations/aula.md` for the overall approach.
    private func handleFormIntercepted(
        form: AulaHTMLForm,
        pageURL: URL,
        cookies: [HTTPCookie],
        userAgent: String?
    ) {
        phase = .verifying
        Task {
            do {
                let result = try await AulaFormWalker.walk(
                    firstForm: form,
                    formPageURL: pageURL,
                    cookies: cookies,
                    expectedState: pkce.state,
                    codeVerifier: pkce.verifier,
                    redirectHost: URL(string: config.redirectURI)?.host ?? AulaOAuth.redirectHost,
                    config: config,
                    userAgent: userAgent,
                    log: { message in
                        AppLogger.debug("\(private: message)", category: .onboarding)
                    }
                )
                try await finish(
                    tokens: result.tokens,
                    cookies: result.cookies,
                    userAgent: userAgent
                )
            } catch {
                fail(error)
            }
        }
    }

    /// Shared tail: build the session, verify it works, and save the integration.
    /// `tokens` is nil on the cookie-only path — the web flow authenticates the
    /// API with the aula.dk session cookies alone, no OAuth code involved.
    /// `cookies` is persisted twice: the API-scoped subset that authenticates
    /// calls, and the full broker/SSO jar (``AulaSession/brokerCookies``) kept
    /// only so a later silent re-authorize can re-walk the authorize chain
    /// without a fresh MitID prompt.
    private func finish(
        tokens: TokenResponse?,
        cookies: [HTTPCookie],
        userAgent: String?
    ) async throws {
        let session = AulaSession(
            accessToken: tokens?.accessToken,
            refreshToken: tokens?.refreshToken,
            expiresAt: tokens?.expiresIn.map { Date.now.addingTimeInterval(TimeInterval($0)) },
            cookies: AulaSessionCookies.apiCookies(from: cookies),
            apiVersion: AulaSession.initialAPIVersion,
            children: [],
            brokerCookies: AulaSessionCookies.brokerCookies(from: cookies),
            userAgent: userAgent
        )

        let apiClient = AulaAPIClient(http: URLSessionAulaHTTP())
        let verified = try await AulaConnectionVerifier.verify(
            session: session,
            apiClient: apiClient
        )

        let integration = Integration(
            typeID: BundledIntegrationType.aula.id,
            accountLabel: accountLabel(for: verified),
            grantedCapabilities: [Capability.aula.rawValue]
        )
        credentialStore.save(verified, for: integration.id)
        modelContext.insert(integration)
        Haptics.success()
        onConnected()
        dismiss()
    }

    private func fail(_ error: Error) {
        failWithMessage(error.localizedDescription)
    }

    private func failWithMessage(_ message: String) {
        phase = .error(message)
        Haptics.error()
    }

    /// A friendly label for the connection — the children's names when we have
    /// them, otherwise just the service name.
    private func accountLabel(for session: AulaSession) -> String {
        let names = session.children.map(\.name).filter { !$0.isEmpty }
        return names.isEmpty
            ? Localized.Integrations.Aula.displayName
            : names.joined(separator: ", ")
    }

    private enum Phase: Equatable {
        case loggingIn
        case verifying
        case error(String)
    }

    /// PKCE verifier/challenge/state, computed once per login attempt.
    private struct LoginPKCE {
        let verifier: String
        let challenge: String
        let state: String

        init() {
            verifier = PKCEUtilities.generateCodeVerifier()
            challenge = PKCEUtilities.generateCodeChallenge(from: verifier)
            state = PKCEUtilities.generateState()
        }
    }
}
