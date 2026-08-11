#if canImport(UIKit)
import SwiftUI
import UIKit

/// A TextKit-backed code renderer. `UITextView` lays out incrementally, unlike SwiftUI
/// `Text`, which keeps long streaming blocks smooth. Unlike prose, code doesn't wrap —
/// long lines extend and the caller scrolls them horizontally.
struct CodeTextView: UIViewRepresentable {
    let attributedText: NSAttributedString
    /// Disabled while streaming, for performance.
    var isSelectable: Bool

    func makeUIView(context: Context) -> CodeTextUIView {
        let view = CodeTextUIView()
        view.isSelectable = isSelectable
        view.setCodeContents(attributedText)
        return view
    }

    func updateUIView(_ view: CodeTextUIView, context: Context) {
        view.isSelectable = isSelectable
        view.setCodeContents(attributedText)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: CodeTextUIView,
        context: Context
    ) -> CGSize? {
        // Ignores the proposed width: code doesn't wrap, so it sizes to its own content.
        uiView.naturalSize()
    }
}

/// Non-wrapping, non-scrolling `UITextView` that sizes to its content. Kept lean: no links,
/// no attachments, no wrapping — just fast incremental layout of monospaced code.
final class CodeTextUIView: UITextView {
    private var cachedSize: CGSize?

    init() {
        super.init(frame: .zero, textContainer: nil)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        isEditable = false
        isScrollEnabled = false
        backgroundColor = .clear
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = 0
        // A wide, fixed container so long lines extend instead of wrapping.
        textContainer.widthTracksTextView = false
        textContainer.lineBreakMode = .byClipping
        textContainer.size = CGSize(width: 1_000_000, height: CGFloat.greatestFiniteMagnitude)

        setContentHuggingPriority(.defaultHigh, for: .vertical)
        setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
    }

    /// Updates the rendered code, skipping the work when nothing changed so a re-render
    /// that didn't touch the text costs nothing.
    func setCodeContents(_ newContents: NSAttributedString) {
        guard attributedText != newContents else { return }
        cachedSize = nil
        attributedText = newContents
        accessibilityLabel = newContents.string
        invalidateIntrinsicContentSize()
    }

    /// The content's own size with no wrapping, cached until the text changes.
    func naturalSize() -> CGSize {
        if let cachedSize {
            return cachedSize
        }
        let unbounded = CGSize(width: 1_000_000, height: CGFloat.greatestFiniteMagnitude)
        let fitted = sizeThatFits(unbounded)
        let size = CGSize(width: fitted.width.rounded(.up), height: fitted.height.rounded(.up))
        cachedSize = size
        return size
    }

    override var intrinsicContentSize: CGSize {
        naturalSize()
    }
}
#endif
