import SafariServices
import SwiftUI

/// An in-app Safari sheet. Used for API-key dashboards and for OAuth consent
/// screens that need Safari's cookies (Sign in with ChatGPT's loopback flow).
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

/// Identifiable wrapper so the sign-in sheet uses one `item`-based state —
/// the URL and the presentation land together.
struct ChatGPTAuthPresentation: Identifiable {
    let id = UUID()
    let url: URL
}
