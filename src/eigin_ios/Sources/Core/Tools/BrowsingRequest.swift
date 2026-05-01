import Foundation

/// A request to browse a URL in a visible WKWebView.
struct BrowsingRequest: Identifiable, Equatable {
    let id: String // tool call ID
    let url: URL
    let toolDisplayName: String
}

/// The result of a browsing request.
enum BrowsingResult {
    case success(String) // extracted text
    case error(String)
    case cancelled
}

/// Async callback that pauses tool execution until the UI finishes browsing.
/// Nil in background contexts (no UI available).
typealias BrowseHandler = @MainActor (BrowsingRequest) async -> BrowsingResult
