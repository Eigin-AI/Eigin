import Factory
import SwiftData
import SwiftUI
import WebKit

/// Sheet for connecting Aula: runs the real UniLogin/MitID login in an
/// interactive `WKWebView` (see ``AulaLoginWebView``), then verifies the
/// resulting session and saves it as an integration. Presented from
/// ``ConnectIntegrationSheet`` when the user picks the Aula type, or from
/// ``IntegrationScreen`` to reconnect an existing account in place. See
/// `docs/src/integrations/aula.md` for why Aula needs a custom web view
/// instead of `ASWebAuthenticationSession`.
struct AddAulaAccount: View {
    /// Invoked after the integration is saved, so the presenting sheet can
    /// dismiss itself too.
    var onConnected: () -> Void = {}
    /// Invoked when the sign-in itself is over and only verification
    /// remains: the presenter replaces this sheet with its own waiting
    /// state. Without it, verification keeps an in-place spinner.
    var onVerifying: (() -> Void)?
    /// Invoked when connecting fails; the presenter shows the failure in
    /// its own design. Without it, the error stays on this sheet.
    var onFailure: ((String) -> Void)?

    let config: PKCEOAuthConfig
    /// The existing integration when this sheet runs as an in-place reconnect
    /// — the new session is saved under its id (so references and keychain
    /// state survive) and its row is updated instead of inserting a new one.
    var existing: Integration?

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
        beginVerifying()
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
                try await finish(tokens: tokens, cookies: cookies)
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
        beginVerifying()
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
                try await finish(tokens: result.tokens, cookies: result.cookies)
            } catch {
                fail(error)
            }
        }
    }

    /// Shared tail: build the session, verify it works, and save the integration.
    /// The OAuth token *is* the session — web cookies are disposable server-side
    /// state re-established from the token when they lapse. A walk that never
    /// minted a token (the cookie-only portal landing) can't be recovered that
    /// way, so it's a failed sign-in: reject it rather than persist a session
    /// doomed to a one-shot cookie lifetime.
    private func finish(
        tokens: TokenResponse?,
        cookies: [HTTPCookie]
    ) async throws {
        guard let tokens else {
            throw AulaConnectionError.sessionRejected
        }
        let session = AulaSession(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            expiresAt: tokens.expiresIn.map { Date.now.addingTimeInterval(TimeInterval($0)) },
            cookies: AulaSessionCookies.apiCookies(from: cookies),
            apiVersion: AulaSession.initialAPIVersion,
            children: []
        )

        let apiClient = AulaAPIClient(http: URLSessionAulaHTTP())
        let verified = try await AulaConnectionVerifier.verify(
            session: session,
            apiClient: apiClient
        )

        if let existing {
            // Reconnect: same id, same keychain namespace — only the labels
            // and the stored session refresh.
            existing.accountLabel = accountLabel(for: verified)
            existing.updatedAt = .now
            credentialStore.save(verified, for: existing.id)
            IntegrationHealthMonitor.shared.clearNeedsReconnect(existing.id)
        } else {
            let integration = Integration(
                typeID: BundledIntegrationType.aula.id,
                accountLabel: accountLabel(for: verified),
                grantedCapabilities: [Capability.aula.rawValue]
            )
            credentialStore.save(verified, for: integration.id)
            modelContext.insert(integration)
        }
        Haptics.success()
        onConnected()
        dismiss()
    }

    private func fail(_ error: Error) {
        failWithMessage(error.localizedDescription)
    }

    /// Hand the wait back to the presenter when it asked for that; the
    /// waiting and failed states are its design, not a login page's.
    private func beginVerifying() {
        if let onVerifying {
            onVerifying()
        } else {
            phase = .verifying
        }
    }

    private func failWithMessage(_ message: String) {
        if let onFailure {
            onFailure(message)
            dismiss()
        } else {
            phase = .error(message)
            Haptics.error()
        }
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
