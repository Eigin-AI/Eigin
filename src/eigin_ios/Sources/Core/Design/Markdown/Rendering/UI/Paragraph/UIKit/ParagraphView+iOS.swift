#if canImport(UIKit)
import SwiftUI

struct ParagraphView: UIViewRepresentable {
    @Environment(\.openURL) var openURL
    @Environment(\.markdownConfig) var config: MarkdownRenderConfig

    var contents: NSMutableAttributedString
    var lineSpacing: CGFloat?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ParagraphUIView {
        let openUrlFunction = openURL.callAsFunction(_:)
        let view = ParagraphViewCache.shared.createOrReuseView(
            contents: contents,
            lineSpacing: lineSpacing
        )
        view.onUrlTap = openUrlFunction
        view.setParagraphContents(contents, lineSpacing: lineSpacing, animatedByWord: false)
        return view
    }

    func updateUIView(_ view: ParagraphUIView, context: Context) {
        if view.paragraphContents != contents || view.lineSpacing != lineSpacing {
            view.setParagraphContents(contents, lineSpacing: lineSpacing, animatedByWord: false)
        }
    }

    /// Without this, SwiftUI falls back to `intrinsicContentSize`, which needs `bounds.width`
    /// already set — it would size the paragraph wrong on the first pass and correct itself
    /// a frame later. Measuring against the proposed width directly avoids that flicker.
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: ParagraphUIView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width > 0, width.isFinite else {
            return nil
        }

        // Check if content or lineSpacing changed - if so, clear the cache
        if contents != context.coordinator.lastContents || lineSpacing != context.coordinator
            .lastLineSpacing
        {
            context.coordinator.sizeCache.removeAll()
            context.coordinator.lastContents = contents
            context.coordinator.lastLineSpacing = lineSpacing
        }

        // Round width to avoid cache misses from floating point precision issues
        let cacheKey = (width * 10).rounded() / 10 // Round to 1 decimal place

        // Check if we have a cached size for this width
        if let cachedSize = context.coordinator.sizeCache[cacheKey] {
            return cachedSize
        }

        // Calculate new size
        let targetSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        let size = uiView.sizeThatFits(targetSize)
        let calculatedSize = CGSize(width: size.width, height: size.height.rounded(.up))

        context.coordinator.sizeCache[cacheKey] = calculatedSize

        return calculatedSize
    }

    class Coordinator {
        // Cache all calculated sizes keyed by width
        var sizeCache: [CGFloat: CGSize] = [:]
        var lastContents: NSMutableAttributedString?
        var lastLineSpacing: CGFloat?
    }
}
#endif
