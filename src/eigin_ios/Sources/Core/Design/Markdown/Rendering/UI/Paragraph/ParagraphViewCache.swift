import Foundation

/// A small pool of reusable paragraph views. Only touched from
/// `ParagraphView.makeUIView`, so it lives on the main actor with the views it
/// vends.
@MainActor
final class ParagraphViewCache {
    private var cachedViews: [MDParagraphView] = []
    private let maxCacheSize = 50

    private init() {}

    static let shared = ParagraphViewCache()

    func createOrReuseView() -> MDParagraphView {
        if let availableView = findAvailableCachedView() {
            return availableView
        }
        let newView = MDParagraphView()
        if cachedViews.count < maxCacheSize {
            cachedViews.append(newView)
        }
        return newView
    }

    private func findAvailableCachedView() -> MDParagraphView? {
        cachedViews.first { view in
            view.superview == nil && view.window == nil
        }
    }
}
