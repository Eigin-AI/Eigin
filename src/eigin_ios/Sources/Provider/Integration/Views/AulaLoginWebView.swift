import SwiftUI
import WebKit

/// The interactive WKWebView that hosts Aula's real UniLogin/MitID login,
/// intercepts the OAuth callback (or a pending SAML form to finish
/// headlessly), and reads the session cookies. See
/// `docs/src/integrations/aula.md` for why this is purpose-built rather than
/// `ASWebAuthenticationSession` or the read-only agentic-browsing web view.
struct AulaLoginWebView: UIViewRepresentable {
    let authorizationURL: URL
    /// The PKCE `state` for this attempt — the callback is detected by
    /// matching this, not just `redirectHost`, since the OS races us for that
    /// host too (see the universal-link race in the integration doc).
    let expectedState: String
    /// Host of the OAuth `redirect_uri` (e.g. `app-private.aula.dk`).
    let redirectHost: String
    let onResult: (_ callbackURL: URL, _ cookies: [HTTPCookie]) -> Void
    /// Fired when a pending SAML/confirm form is intercepted before it would
    /// navigate to `redirectHost` — see `AulaFormWalker`.
    let onFormIntercepted: (
        _ form: AulaHTMLForm,
        _ pageURL: URL,
        _ cookies: [HTTPCookie],
        _ userAgent: String?
    ) -> Void
    /// Fired when the interactive login can't continue and there's no page left
    /// to recover a pending form from.
    let onError: (_ message: String) -> Void
    /// Bumped by ``AddAulaAccount`` on foreground to nudge a redraw (see
    /// ``updateUIView``).
    let wakeToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(
            expectedState: expectedState,
            redirectHost: redirectHost,
            onResult: onResult,
            onFormIntercepted: onFormIntercepted,
            onError: onError
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        // A fresh, non-persistent store so each login starts clean and its
        // cookies stay isolated from any other web content in the app.
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(
            context.coordinator,
            name: Coordinator.messageHandlerName
        )
        configuration.userContentController.addUserScript(Coordinator.interceptScript)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.load(URLRequest(url: authorizationURL))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Recovers from the WKWebView backgrounding quirk (see the
        // integration doc) with a pure redraw — deliberately not a reload,
        // which would throw away the in-flight MitID challenge.
        guard context.coordinator.lastWakeToken != wakeToken else { return }
        context.coordinator.lastWakeToken = wakeToken
        uiView.setNeedsLayout()
        uiView.layoutIfNeeded()
        // Some devices need the layer tree rebuilt, not just relaid-out; an
        // imperceptible opacity nudge forces that.
        uiView.alpha = 0.999
        DispatchQueue.main.async { uiView.alpha = 1 }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        static let messageHandlerName = "aulaForm"

        /// Overrides `HTMLFormElement.prototype.submit` to catch the first
        /// Aula-bound SAML auto-submit form without letting it fire (per
        /// spec, `.submit()` bypasses the `submit` event, so an `onsubmit`
        /// handler can't stop it) — see the headless SAML tail section of
        /// `docs/src/integrations/aula.md` for why this hop specifically.
        static let interceptScript = WKUserScript(
            source: #"""
            (function () {
              var relayed = false;
              function serialize(form) {
                var fields = {};
                var inputs = form.querySelectorAll('input');
                for (var i = 0; i < inputs.length; i++) {
                  var el = inputs[i];
                  if (el.name) fields[el.name] = el.value;
                }
                // Always send RelayState, even empty, rather than omitting it.
                if (!('RelayState' in fields)) fields['RelayState'] = '';
                return {
                  action: form.getAttribute('action') || '',
                  fields: fields,
                  url: String(window.location.href),
                  userAgent: String(navigator.userAgent)
                };
              }
              // Two SAML auto-submit forms appear in this chain; only the one
              // headed to Aula (not the broker itself) is ours to take over.
              function isAulaBound(form) {
                var action = form.getAttribute('action') || '';
                return action.indexOf('aula.dk') >= 0;
              }
              function looksRelevant(form) {
                if (!form) return false;
                return isAulaBound(form) && !!form.querySelector('input[name="SAMLResponse"]');
              }
              function relay(form) {
                if (relayed) return;
                relayed = true;
                window.webkit.messageHandlers.\#(messageHandlerName).postMessage(serialize(form));
              }
              var originalSubmit = window.HTMLFormElement.prototype.submit;
              window.HTMLFormElement.prototype.submit = function () {
                if (looksRelevant(this)) { relay(this); return; }
                return originalSubmit.apply(this, arguments);
              };
              // Belt-and-suspenders for a real submit-button click, which does
              // go through the `submit` event.
              document.addEventListener('submit', function (event) {
                if (looksRelevant(event.target)) {
                  event.preventDefault();
                  relay(event.target);
                }
              }, true);
              // Fallback scan in case a page renders the form but never calls
              // submit()/fires the event on its own.
              function scan() {
                var forms = document.forms;
                for (var i = 0; i < forms.length; i++) {
                  if (looksRelevant(forms[i])) { relay(forms[i]); return; }
                }
              }
              if (document.readyState !== 'loading') { scan(); }
              document.addEventListener('DOMContentLoaded', scan, true);
            })();
            """#,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )

        private let expectedState: String
        private let redirectHost: String
        private let onResult: (URL, [HTTPCookie]) -> Void
        private let onFormIntercepted: (AulaHTMLForm, URL, [HTTPCookie], String?) -> Void
        private let onError: (String) -> Void
        /// The last ``AulaLoginWebView/wakeToken`` acted on, so
        /// ``AulaLoginWebView/updateUIView`` only nudges on a new wake.
        var lastWakeToken = 0
        /// Guards against firing the result twice if the callback URL triggers
        /// more than one navigation event.
        private var didFinish = false

        init(
            expectedState: String,
            redirectHost: String,
            onResult: @escaping (URL, [HTTPCookie]) -> Void,
            onFormIntercepted: @escaping (AulaHTMLForm, URL, [HTTPCookie], String?) -> Void,
            onError: @escaping (String) -> Void
        ) {
            self.expectedState = expectedState
            self.redirectHost = redirectHost
            self.onResult = onResult
            self.onFormIntercepted = onFormIntercepted
            self.onError = onError
        }

        // MARK: - WKScriptMessageHandler

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard !didFinish,
                  let webView = message.webView,
                  let payload = message.body as? [String: Any],
                  let urlString = payload["url"] as? String,
                  let pageURL = URL(string: urlString)
            else { return }

            let action = payload["action"] as? String ?? ""
            let fields = payload["fields"] as? [String: String] ?? [:]
            let userAgent = payload["userAgent"] as? String
            didFinish = true
            captureCookies(from: webView) { cookies in
                self.onFormIntercepted(
                    AulaHTMLForm(action: action, fields: fields),
                    pageURL,
                    cookies,
                    userAgent
                )
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let items = components?.queryItems ?? []
            let echoesOurState = items.contains { $0.name == "state" && $0.value == expectedState }
            let code = items.first { $0.name == "code" }?.value
            let host = url.host?.lowercased() ?? ""
            let isCallbackHost = host == redirectHost.lowercased()

            // The OAuth callback: cancel in-web-view so neither the OS nor we
            // hand the code to the installed Aula app (universal-link race).
            if !didFinish, code != nil, echoesOurState || isCallbackHost {
                didFinish = true
                decisionHandler(.cancel)
                captureCookies(from: webView) { cookies in
                    self.onResult(url, cookies)
                }
                return
            }

            // The redirect host without a code yet — same reasoning, keep it
            // in-web-view rather than risk the universal-link hand-off.
            if !didFinish, isCallbackHost {
                decisionHandler(.cancel)
                return
            }

            // MitID and some IdPs hand off to a native app via a non-web
            // scheme; open those externally so login can continue there —
            // except an Aula host/scheme, which is the callback bounce above.
            if let scheme = url.scheme?.lowercased(),
               scheme != "http", scheme != "https", !didFinish
            {
                if !(host.contains("aula.dk") || scheme.contains("aula")) {
                    UIApplication.shared.open(url)
                }
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        // MARK: - WKUIDelegate

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            // The harder half of the backgrounding quirk (see the integration
            // doc): the content process was actually torn down, so reload now
            // rather than waiting for the next foreground event.
            guard !didFinish else { return }
            webView.reload()
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            // An interrupted load past this point means the interception
            // script didn't catch a pending form in time — the one case we
            // can't recover headlessly, since the page is gone.
            guard !didFinish else { return }
            didFinish = true
            onError(Localized.Errors.Aula.sessionRejected)
        }

        private func captureCookies(
            from webView: WKWebView,
            completion: @escaping ([HTTPCookie]) -> Void
        ) {
            // All cookies, not just aula.dk — the headless walk needs each
            // host's session cookie from the SAML chain.
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                completion(cookies)
            }
        }
    }
}
