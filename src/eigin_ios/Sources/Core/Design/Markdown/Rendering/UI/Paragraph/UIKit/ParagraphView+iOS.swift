#if canImport(UIKit)
import SwiftUI

/// A markdown block's text, laid out in the line boxes of the typography it carries.
struct ParagraphView: View {
    var contents: NSMutableAttributedString

    var body: some View {
        let fonts = contents.leadingTextFonts
        let lineBox = fonts.flatMap { fonts in
            fonts.preferredLineHeight.map { ParagraphLineBox(font: fonts.normal, lineHeight: $0) }
        }
        ParagraphTextView(contents: contents, lineBox: lineBox)
            .offset(y: lineBox.map { $0.font.textKitShift(lineHeight: $0.lineHeight) } ?? 0)
    }
}

/// Exact line height for a paragraph, with the font that centres glyphs in it.
struct ParagraphLineBox: Equatable {
    let font: MDFont
    let lineHeight: CGFloat
}

private struct ParagraphTextView: UIViewRepresentable {
    @Environment(\.openURL) var openURL

    var contents: NSMutableAttributedString
    var lineBox: ParagraphLineBox?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ParagraphUIView {
        let openUrlFunction = openURL.callAsFunction(_:)
        let view = ParagraphViewCache.shared.createOrReuseView()
        view.onUrlTap = openUrlFunction
        view.setParagraphContents(contents, lineBox: lineBox, animatedByWord: false)
        return view
    }

    func updateUIView(_ view: ParagraphUIView, context: Context) {
        if view.paragraphContents != contents || view.lineBox != lineBox {
            view.setParagraphContents(contents, lineBox: lineBox, animatedByWord: false)
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

        // Check if content or line box changed - if so, clear the cache
        if contents != context.coordinator.lastContents || lineBox != context.coordinator
            .lastLineBox
        {
            context.coordinator.sizeCache.removeAll()
            context.coordinator.lastContents = contents
            context.coordinator.lastLineBox = lineBox
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
        var lastLineBox: ParagraphLineBox?
    }
}
#endif
