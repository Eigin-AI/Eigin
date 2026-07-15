import Foundation

/// Walks the credential-free tail of Aula's login — the SAML/broker form
/// hand-offs after MitID has already authenticated — entirely headlessly, so
/// no browser ever navigates to the `app-private.aula.dk` callback. Picks up
/// where the interactive web view stops: the pending auto-submit form's HTML
/// and the cookies the web view's MitID login already established. See
/// `docs/src/integrations/aula.md` for why this exists.
///
/// Ends one of two ways: reaching the OIDC callback (exchanges the code
/// against the caller's PKCE verifier/state), or — more commonly — landing on
/// `www.aula.dk/portal/` with no code at all, which is itself success; the
/// accumulated cookie jar is what ``AulaConnectionVerifier`` then checks.
enum AulaFormWalker {
    /// How many hops (redirects + form resubmits combined) we'll follow before
    /// giving up — a guard against an unexpected loop in the chain.
    static let maxHops = 15

    struct Result {
        /// OAuth tokens, when the walk reached the OIDC callback. `nil` on the
        /// cookie-only success path: the browser web flow never mints a code
        /// at all — it lands on `www.aula.dk/portal/` and drives the API with
        /// the `PHPSESSID`/`Csrfp-Token` cookies alone — so a walk that ends
        /// there with those cookies in the jar is a successful login, not a
        /// failure.
        let tokens: TokenResponse?
        /// The walk's final cookie jar — includes whatever the SAML/broker
        /// hops set (e.g. the `www.aula.dk` session, `Csrfp-Token`), which the
        /// API client needs alongside the tokens.
        let cookies: [HTTPCookie]
    }

    /// - Parameters:
    ///   - firstForm: the pending auto-submit form the web view was about to
    ///     submit when we intercepted it (extracted from the page via a
    ///     content script — see ``AddAulaAccount``).
    ///   - formPageURL: that page's URL, used to resolve a relative form
    ///     `action`.
    ///   - cookies: cookies captured from the web view at the moment of
    ///     interception.
    ///   - expectedState: the web view's original PKCE `state`.
    ///   - codeVerifier: the web view's original PKCE `verifier`.
    ///   - redirectHost: host of the OAuth `redirect_uri`
    ///     (`app-private.aula.dk`) — the walk's terminus.
    /// - Parameter log: called with a one-line description of each hop, for
    ///   debugging against this third-party chain we don't control.
    static func walk(
        firstForm: AulaHTMLForm,
        formPageURL: URL,
        cookies: [HTTPCookie],
        expectedState: String,
        codeVerifier: String,
        redirectHost: String,
        config: PKCEOAuthConfig,
        http: AulaFormWalkerHTTP? = nil,
        urlSession: URLSession = .shared,
        userAgent: String? = nil,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> Result {
        let client = http ?? URLSessionAulaFormWalkerHTTP(cookies: cookies, userAgent: userAgent)

        log(
            "walk: cookies for broker.unilogin.dk: \(cookieNames(cookies, forHostContaining: "unilogin.dk"))"
        )
        log(
            "walk: cookies for nemlog-in.mitid.dk: \(cookieNames(cookies, forHostContaining: "mitid.dk"))"
        )
        log("walk: cookies for aula.dk: \(cookieNames(cookies, forHostContaining: "aula.dk"))")
        logSAMLResponse(in: firstForm, log: log)
        log(
            "walk: POST \(describeAction(firstForm, relativeTo: formPageURL)) fields=\(firstForm.fields.keys.sorted())"
        )
        let response = try await post(firstForm, relativeTo: formPageURL, client: client)
        log("walk: ← \(response.statusCode) \(response.url.absoluteString)")

        return try await drive(
            initialResponse: response,
            client: client,
            autoFormsOnly: false,
            seedCookies: cookies,
            expectedState: expectedState,
            codeVerifier: codeVerifier,
            redirectHost: redirectHost,
            config: config,
            urlSession: urlSession,
            log: log
        )
    }

    /// Re-walks the OIDC authorize chain from scratch, using the broker/SSO
    /// cookie jar captured at the original login (``AulaSession/brokerCookies``)
    /// rather than a fresh MitID challenge. If that broker session is still
    /// alive, it silently SSOs and this reaches the OIDC callback the same way
    /// ``walk`` does after its intercepted form — no user interaction. If the
    /// broker session has lapsed, the chain lands on an interactive page
    /// (MitID prompt, IdP selection) instead of an auto-submit form; that's
    /// treated as failure (``AulaConnectionError/sessionRejected``) rather than
    /// resubmitted, since there's no credential to complete it headlessly. See
    /// ``AulaReauthorizer``, the caller.
    ///
    /// - Parameters:
    ///   - authorizationURL: a freshly-built OIDC authorize URL (fresh PKCE
    ///     material — the code this mints must match its own verifier/state,
    ///     distinct from whatever the original login used).
    ///   - brokerCookies: the broker/SSO jar from ``AulaSession/brokerCookies``,
    ///     seeded into a fresh ephemeral cookie jar for this walk.
    static func reauthorize(
        authorizationURL: URL,
        brokerCookies: [HTTPCookie],
        expectedState: String,
        codeVerifier: String,
        redirectHost: String,
        config: PKCEOAuthConfig,
        http: AulaFormWalkerHTTP? = nil,
        urlSession: URLSession = .shared,
        userAgent: String? = nil,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> Result {
        let client = http ?? URLSessionAulaFormWalkerHTTP(
            cookies: brokerCookies,
            userAgent: userAgent
        )

        log("reauthorize: GET \(authorizationURL.absoluteString)")
        let response = try await client.get(authorizationURL)
        log("reauthorize: ← \(response.statusCode) \(response.url.absoluteString)")

        return try await drive(
            initialResponse: response,
            client: client,
            autoFormsOnly: true,
            seedCookies: brokerCookies,
            expectedState: expectedState,
            codeVerifier: codeVerifier,
            redirectHost: redirectHost,
            config: config,
            urlSession: urlSession,
            log: log
        )
    }

    /// Shared hop loop for ``walk`` and ``reauthorize``: follows redirects,
    /// resubmits auto-submit forms, and terminates on either the OIDC callback
    /// or a formless landing on `aula.dk` (the portal — cookie-only success).
    ///
    /// - Parameter autoFormsOnly: when `true` (``reauthorize``'s silent
    ///   re-authorize), only ``AulaHTMLParsing/confirmationForm`` and
    ///   ``AulaHTMLParsing/samlForm`` are followed — never the generic
    ///   ``AulaHTMLParsing/anyForm`` fallback ``walk`` uses, which would
    ///   otherwise resubmit an interactive MitID/IdP-selection page as if it
    ///   were an auto-submit hop.
    private static func drive(
        initialResponse: AulaFormWalkerResponse,
        client: AulaFormWalkerHTTP,
        autoFormsOnly: Bool,
        seedCookies: [HTTPCookie],
        expectedState: String,
        codeVerifier: String,
        redirectHost: String,
        config: PKCEOAuthConfig,
        urlSession: URLSession,
        log: @escaping @Sendable (String) -> Void
    ) async throws -> Result {
        var response = initialResponse

        for _ in 0 ..< maxHops {
            if let callbackURL = try callbackURL(from: response, redirectHost: redirectHost) {
                log("walk: reached callback \(callbackURL.absoluteString)")
                let code = try PKCEOAuthFlow.validateCallback(
                    callbackURL,
                    expectedState: expectedState
                )
                let tokens = try await PKCEOAuthFlow.exchangeCode(
                    code: code,
                    codeVerifier: codeVerifier,
                    config: config,
                    urlSession: urlSession
                )
                // The token authenticates basic reads, but Aula's *sensitive*
                // endpoints (messaging, calendar) need the real web session:
                // a `Csrfp-Token` cookie (only ever set by loading the portal,
                // never by an API response) for the calendar POST's CSRF
                // header, plus the `PHPSESSID` the session runs on. The OIDC
                // path minted a code without touching the portal, so warm it
                // now over the authenticated jar to capture those cookies.
                await warmWebSession(client: client, log: log)
                let finalCookies = (client as? URLSessionAulaFormWalkerHTTP)?
                    .currentCookies ?? seedCookies
                return Result(tokens: tokens, cookies: finalCookies)
            }

            if (300 ... 399).contains(response.statusCode) {
                guard let location = response.location else {
                    log(
                        "walk: \(response.statusCode) with no Location — body: \(snippet(response.body))"
                    )
                    throw AulaConnectionError.unexpectedResponse
                }
                log("walk: GET \(location.absoluteString)")
                response = try await client.get(location)
                log("walk: ← \(response.statusCode) \(response.url.absoluteString)")
                continue
            }

            guard response.statusCode == 200 else {
                log("walk: unexpected \(response.statusCode) — body: \(snippet(response.body))")
                throw AulaConnectionError.requestFailed(
                    "Unexpected status \(response.statusCode): \(snippet(response.body, limit: 300))"
                )
            }

            let nextForm = AulaHTMLParsing.confirmationForm(in: response.body)
                ?? AulaHTMLParsing.samlForm(in: response.body)
                ?? (autoFormsOnly ? nil : AulaHTMLParsing.anyForm(in: response.body))
            guard let nextForm else {
                // A formless 200 on an aula.dk host is the portal landing
                // page — and this is where the real browser login *ends*. It
                // never mints an OAuth code: the web app drives the API purely
                // with the aula.dk web-session cookies (`PHPSESSID` +
                // `Csrfp-Token`) set across the SAML→portal redirects. So
                // reaching the portal *is* success; we hand the accumulated jar
                // to ``AulaConnectionVerifier``, which is the real arbiter of
                // whether the session works.
                //
                // In silent-re-authorize mode, landing anywhere else with no
                // auto-submit form means the broker session is gone and we've
                // hit an interactive page (MitID prompt, IdP selection) — that
                // falls into the same non-aula.dk branch below and surfaces as
                // `sessionRejected`, same as a genuinely rejected session.
                let host = response.url.host?.lowercased() ?? ""
                guard host.hasSuffix("aula.dk") else {
                    log("walk: no form/callback on 200 page — body: \(snippet(response.body))")
                    throw AulaConnectionError.sessionRejected
                }
                let finalCookies = (client as? URLSessionAulaFormWalkerHTTP)?
                    .currentCookies ?? seedCookies
                log(
                    "walk: reached portal on \(host) — jar: \(cookieNames(finalCookies, forHostContaining: "aula.dk"))"
                )
                log("walk: succeeding cookie-only (\(finalCookies.count) cookies)")
                return Result(tokens: nil, cookies: finalCookies)
            }
            log(
                "walk: POST \(describeAction(nextForm, relativeTo: response.url)) fields=\(nextForm.fields.keys.sorted())"
            )
            response = try await post(nextForm, relativeTo: response.url, client: client)
            log("walk: ← \(response.statusCode) \(response.url.absoluteString)")
        }

        throw AulaConnectionError.requestFailed("SAML chain exceeded \(maxHops) hops")
    }

    /// Loads `www.aula.dk/portal/` through the authenticated jar so the
    /// web-session cookies (`PHPSESSID`, `Csrfp-Token`) land in it — needed by
    /// the sensitive endpoints. Best-effort: a hiccup here is logged and
    /// swallowed rather than failing login, since we already hold valid tokens.
    private static func warmWebSession(
        client: AulaFormWalkerHTTP,
        log: @escaping @Sendable (String) -> Void
    ) async {
        guard let portal = URL(string: "https://www.aula.dk/portal/") else { return }
        do {
            var response = try await client.get(portal)
            log("walk: warm portal ← \(response.statusCode) \(response.url.absoluteString)")
            var hops = 0
            while (300 ... 399).contains(response.statusCode),
                  let location = response.location,
                  hops < maxHops
            {
                hops += 1
                response = try await client.get(location)
                log("walk: warm portal ← \(response.statusCode) \(response.url.absoluteString)")
            }
        } catch {
            log("walk: warm portal failed: \(error.localizedDescription)")
        }
    }

    private static func cookieNames(
        _ cookies: [HTTPCookie],
        forHostContaining substring: String
    ) -> [String] {
        cookies.filter { $0.domain.contains(substring) }.map { "\($0.name)@\($0.domain)" }.sorted()
    }

    /// Logs the SAML assertion's own attributes (`Destination`,
    /// `InResponseTo`, validity window) for diagnosing a rejection against
    /// what the broker itself checks.
    private static func logSAMLResponse(in form: AulaHTMLForm, log: (String) -> Void) {
        guard let raw = form.fields["SAMLResponse"] else { return }
        guard let data = Data(base64Encoded: raw, options: .ignoreUnknownCharacters),
              let xml = String(data: data, encoding: .utf8)
        else {
            log("walk: SAMLResponse present but could not base64-decode (len=\(raw.count))")
            return
        }
        let attrs = [
            "Destination",
            "InResponseTo",
            "IssueInstant",
            "ID",
            "NotOnOrAfter",
            "NotBefore",
        ]
        let parts = attrs.compactMap { name in
            attributeValue(name, in: xml).map { "\(name)=\($0)" }
        }
        log("walk: SAMLResponse \(parts.joined(separator: " "))")
        if let relay = form.fields["RelayState"] {
            log("walk: RelayState=\(relay)")
        }
    }

    private static func attributeValue(_ name: String, in xml: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"\b\#(name)="([^"]*)""#) else {
            return nil
        }
        let ns = xml as NSString
        guard let match = regex.firstMatch(in: xml, range: NSRange(location: 0, length: ns.length)),
              match.range(at: 1).location != NSNotFound
        else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    private static func describeAction(_ form: AulaHTMLForm, relativeTo pageURL: URL) -> String {
        form.action.isEmpty
            ? pageURL.absoluteString
            : (URL(string: form.action, relativeTo: pageURL)?.absoluteString ?? form.action)
    }

    /// A short, single-line-safe excerpt of a response body for logging.
    /// Strips all markup first — an error page's actual text (title, heading,
    /// instruction) is usually preceded by a `<head>` full of `<meta>`/`<link>`
    /// tags that, left in, blow through any reasonable truncation limit before
    /// a single word of the real message appears. What's left over after
    /// stripping is exactly the page's visible text content, in document
    /// order — robust to whatever theme/markup this specific broker uses,
    /// unlike matching a guessed element id/class.
    private static func snippet(_ body: String, limit: Int = 800) -> String {
        let text = body
            .replacingOccurrences(
                of: #"<(script|style)\b[\s\S]*?</\1>"#,
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count > limit ? String(text.prefix(limit)) + "…" : text
    }

    /// A `3xx` to the callback host carrying `code` is the terminus; some
    /// flows also land there directly with a `200` (rare, but the reference
    /// implementation guards for it too).
    private static func callbackURL(
        from response: AulaFormWalkerResponse,
        redirectHost: String
    ) throws -> URL? {
        if let location = response.location,
           location.host?.lowercased() == redirectHost.lowercased(),
           hasCode(location)
        {
            return location
        }
        if response.statusCode == 200,
           response.url.host?.lowercased() == redirectHost.lowercased(),
           hasCode(response.url)
        {
            return response.url
        }
        return nil
    }

    private static func hasCode(_ url: URL) -> Bool {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.contains { $0.name == "code" } ?? false
    }

    private static func post(
        _ form: AulaHTMLForm,
        relativeTo pageURL: URL,
        client: AulaFormWalkerHTTP
    ) async throws -> AulaFormWalkerResponse {
        let actionURL = form.action.isEmpty
            ? pageURL
            : (URL(string: form.action, relativeTo: pageURL)?.absoluteURL ?? pageURL)
        // Match the reference client: a SAML form always sends `RelayState`,
        // even as an empty string, rather than omitting the key entirely when
        // the source HTML didn't render one.
        var fields = form.fields
        if fields["SAMLResponse"] != nil, fields["RelayState"] == nil {
            fields["RelayState"] = ""
        }
        return try await client.post(actionURL, form: fields, referer: pageURL)
    }
}
