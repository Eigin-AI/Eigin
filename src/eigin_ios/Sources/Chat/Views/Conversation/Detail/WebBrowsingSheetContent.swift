import SwiftUI
import WebKit

/// Displays a WKWebView for agent-driven web browsing.
///
/// Multi-phase experience:
/// 1. Input bar expands, status text visible while page loads
/// 2. Once the page has initial content (`didCommit`), web view fades in
/// 3. Scanning overlay sweeps while the agent extracts text
/// 4. After extraction, scanning stops and page lingers briefly
/// 5. Completion fires, input bar transitions back to normal
struct WebBrowsingSheetContent: View {
    let request: BrowsingRequest
    let onComplete: (BrowsingResult) -> Void
    var onPageReadyChanged: ((Bool) -> Void)?

    @State private var pageReady = false
    /// Guards against double-completion (linger vs display timeout race).
    @State private var completed = false

    /// How long to keep the page visible after reading completes.
    private let lingerDuration: Duration = .seconds(2)
    /// Maximum time the browsing view stays on screen before auto-completing.
    private let maxDisplayDuration: Duration = .seconds(20)

    var body: some View {
        BrowsingWebView(
            url: request.url,
            onCommit: { handlePageCommit() },
            onResult: { result in handleWebViewResult(result) }
        )
        .containerRelativeFrame(.vertical) { height, _ in height }
        .allowsHitTesting(false)
        .opacity(pageReady ? 1 : 0)
        .animation(Animations.gentle, value: pageReady)
        .onAppear {
            startDisplayTimeout()
        }
    }

    // MARK: - Phase Transitions

    /// Called when WKWebView has received initial content and started rendering.
    private func handlePageCommit() {
        guard !pageReady else { return }
        pageReady = true
        onPageReadyChanged?(true)
    }

    /// Called when WKWebView has finished loading and text has been extracted.
    private func handleWebViewResult(_ result: BrowsingResult) {
        guard !completed else { return }
        // Ensure page is shown even if didCommit was somehow missed
        if !pageReady { handlePageCommit() }
        // Linger so the user can see the page, then complete
        Task {
            try? await Task.sleep(for: lingerDuration)
            complete(with: result)
        }
    }

    /// Auto-completes if the page hasn't resolved in time.
    private func startDisplayTimeout() {
        Task {
            try? await Task.sleep(for: maxDisplayDuration)
            complete(with: .error("Browsing timed out."))
        }
    }

    private func complete(with result: BrowsingResult) {
        guard !completed else { return }
        completed = true
        onComplete(result)
    }
}

// MARK: - WKWebView Wrapper

private struct BrowsingWebView: UIViewRepresentable {
    let url: URL
    let onCommit: () -> Void
    let onResult: (BrowsingResult) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCommit: onCommit, onResult: onResult)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onCommit: () -> Void
        let onResult: (BrowsingResult) -> Void
        private var didComplete = false
        private var committed = false
        private var pollTask: Task<Void, Never>?
        private var timeoutTask: Task<Void, Never>?

        /// Minimum character count to consider extracted text "meaningful".
        private let minTextLength = 50
        /// How often to poll for text after commit.
        private let pollInterval: Duration = .milliseconds(800)
        /// Hard timeout — if nothing useful extracted by this point, give up.
        private let timeout: Duration = .seconds(8)

        init(onCommit: @escaping () -> Void, onResult: @escaping (BrowsingResult) -> Void) {
            self.onCommit = onCommit
            self.onResult = onResult
            super.init()
            startTimeout()
        }

        deinit {
            pollTask?.cancel()
            timeoutTask?.cancel()
        }

        /// The web view has received initial data and begun rendering.
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            guard !committed else { return }
            committed = true
            onCommit()
            startPolling(webView)
        }

        /// Page fully loaded — do one final extraction attempt.
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                await extractText(from: webView)
            }
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            finish(.error("Page failed to load: \(error.localizedDescription)"))
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            finish(.error("Page failed to load: \(error.localizedDescription)"))
        }

        // MARK: - Eager Polling

        private func startPolling(_ webView: WKWebView) {
            pollTask = Task { @MainActor [weak webView] in
                try? await Task.sleep(for: .milliseconds(500))

                while !Task.isCancelled {
                    guard let webView else { return }
                    await extractText(from: webView)
                    if didComplete { return }
                    try? await Task.sleep(for: pollInterval)
                }
            }
        }

        @MainActor
        private func extractText(from webView: WKWebView) async {
            guard !didComplete else { return }
            do {
                let raw = try await webView
                    .evaluateJavaScript("document.body.innerText") as? String ?? ""
                let sanitized = HTMLSanitizer.sanitize(raw)
                if sanitized.text.count >= minTextLength {
                    finish(.success(sanitized.text))
                }
            } catch {
                // JS eval can fail transiently during load — keep polling
            }
        }

        // MARK: - Timeout

        private func startTimeout() {
            timeoutTask = Task { @MainActor in
                try? await Task.sleep(for: timeout)
                guard !didComplete else { return }
                finish(.error("Page took too long to load."))
            }
        }

        private func finish(_ result: BrowsingResult) {
            guard !didComplete else { return }
            didComplete = true
            pollTask?.cancel()
            timeoutTask?.cancel()
            onResult(result)
        }
    }
}
