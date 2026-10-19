#if canImport(UIKit)
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private struct CachedParagraphUIViewSize {
    let size: CGSize
    let targetWidth: CGFloat
}

class ParagraphUIView: UITextView {
    private(set) var paragraphContents: NSMutableAttributedString = .init()
    private(set) var lineBox: ParagraphLineBox?
    private var cachedSize: CachedParagraphUIViewSize?

    /// To override the behaviour of this property, do so on ParagraphView's SwiftUI wrapper.
    var onUrlTap: (URL) -> Void = { UIApplication.shared.open($0) }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        delegate = self
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        delegate = self
        setupView()
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        // Fix for crash: "UIPreviewTarget requires that the container view is in a window". When
        // the view is removed from the window (e.g. scrolled out in LazyVStack), we should clear
        // the selection to prevent any pending menu or drag interactions from trying to reference
        // the detached view.
        if newWindow == nil {
            selectedTextRange = nil
        }
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            selectedTextRange = nil
        }
        return result
    }

    override var intrinsicContentSize: CGSize {
        if let cachedSize {
            return cachedSize.size
        }
        var targetWidth = bounds.width
        if targetWidth <= 0 || targetWidth.isInfinite {
            // When bounds.width is not valid, we have to give a best guess, otherwise Chat becomes
            // blank in some cases sometimes. It may be related to LazyVStack.
            targetWidth = window?.windowScene?.screen.bounds.width ?? 320
        }
        let targetSize = CGSize(width: targetWidth, height: .greatestFiniteMagnitude)
        let contentSize = sizeThatFits(targetSize)
        let roundedUpSize = CGSize(
            width: contentSize.width.rounded(.up),
            height: contentSize.height.rounded(.up)
        )
        cachedSize = CachedParagraphUIViewSize(size: roundedUpSize, targetWidth: targetWidth)
        return roundedUpSize
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width != cachedSize?.targetWidth {
            invalidateCachedSize()
        }
        invalidateIntrinsicContentSize()
    }

    func setParagraphContents(
        _ newContents: NSMutableAttributedString,
        lineBox: ParagraphLineBox? = nil,
        animatedByWord: Bool
    ) {
        guard paragraphContents != newContents || self.lineBox != lineBox else {
            return
        }
        paragraphContents = newContents
        self.lineBox = lineBox

        let oldAttributedString: NSAttributedString = attributedText
        let finalString: NSMutableAttributedString = if let lineBox {
            applyLineBox(lineBox, to: newContents)
        } else {
            newContents
        }

        guard finalString != oldAttributedString else {
            return
        }

        invalidateCachedSize()
        attributedText = finalString

        configureAccessibility(for: finalString)

        invalidateIntrinsicContentSize()
    }

    private func applyLineBox(
        _ lineBox: ParagraphLineBox,
        to attributedString: NSMutableAttributedString
    ) -> NSMutableAttributedString {
        let result = NSMutableAttributedString(attributedString: attributedString)
        result.setLineBox(lineBox)
        return result
    }

    private func setupView() {
        // Only register if not already registered to prevent conflicts
        if NSTextAttachment
            .textAttachmentViewProviderClass(forFileType: UTType.data.identifier) == nil
        {
            NSTextAttachment.registerViewProviderClass(
                LatexViewProvider.self,
                forFileType: UTType.data.identifier
            )
        }

        isEditable = false
        isSelectable = true
        isScrollEnabled = false
        textAlignment = .left
        backgroundColor = .clear
        if #available(iOS 18.0, *) {
            writingToolsBehavior = .none
        }

        setContentHuggingPriority(.defaultHigh, for: .vertical)
        setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = true
        textContainer.maximumNumberOfLines = 0
        textContainer.lineBreakMode = .byWordWrapping

        // When this is empty, UITextView will not override the styles set by attributes
        linkTextAttributes = [:]

        // Disable drag interaction to prevent crashes related to dragging from a view that might
        // disappear
        textDragInteraction?.isEnabled = false
    }

    /// Configure the accessibility label from the rendered text.
    private func configureAccessibility(for attributedString: NSAttributedString) {
        accessibilityLabel = attributedString.string
        accessibilityCustomActions = nil
    }

    private func invalidateCachedSize() {
        cachedSize = nil
    }
}

// MARK: - UITextViewDelegate

extension ParagraphUIView: UITextViewDelegate {
    func textView(
        _ textView: UITextView,
        primaryActionFor textItem: UITextItem,
        defaultAction: UIAction
    ) -> UIAction? {
        guard case .link(let url) = textItem.content else {
            return defaultAction
        }
        // Replace the default open action so taps route through `onUrlTap`.
        return UIAction { [weak self] _ in
            self?.onUrlTap(url)
        }
    }
}

fileprivate extension NSMutableAttributedString {
    func setLineBox(_ lineBox: ParagraphLineBox) {
        let paragraphStyle = lineBox.font.paragraphStyle(lineHeight: lineBox.lineHeight)
        paragraphStyle.alignment = .left
        addAttribute(
            .paragraphStyle,
            value: paragraphStyle,
            range: NSRange(location: 0, length: length)
        )
    }
}
#endif
