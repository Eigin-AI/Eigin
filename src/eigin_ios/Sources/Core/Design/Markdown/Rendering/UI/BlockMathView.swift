import iosMath
import SwiftUI

#if canImport(UIKit)

struct BlockMathView: UIViewRepresentable {
    let latex: String
    let color: Color
    let pointSize: CGFloat

    init(
        latex: String,
        color: Color = .primary,
        pointSize: CGFloat = UIFont.preferredFont(forTextStyle: .body).pointSize
    ) {
        self.latex = latex
        self.color = color
        self.pointSize = pointSize
    }

    func makeUIView(context: Context) -> MTMathUILabel {
        let label = MTMathUILabel()
        label.latex = latex
        label.textColor = UIColor(color)
        label.displayErrorInline = false
        label.fontSize = pointSize
        label.setContentHuggingPriority(.defaultHigh, for: .vertical)
        return label
    }

    func updateUIView(_ uiView: MTMathUILabel, context: Context) {
        uiView.textColor = UIColor(color)
        uiView.latex = latex
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: MTMathUILabel,
        context: Context
    ) -> CGSize? {
        uiView.sizeToFit()
        let size = uiView.bounds.size
        // It's a known issue that MTMathUILabel may be cut off for some short statement. Manually
        // add 1 to the height fix it.
        return CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up) + 1)
    }
}

#elseif canImport(AppKit)

struct BlockMathView: NSViewRepresentable {
    let latex: String
    let color: Color
    let pointSize: CGFloat

    init(
        latex: String,
        color: Color = .primary,
        pointSize: CGFloat = UIFont.preferredFont(forTextStyle: .body).pointSize
    ) {
        self.latex = latex
        self.color = color
        self.pointSize = pointSize
    }

    func makeNSView(context: Context) -> MTMathUILabel {
        let label = MTMathUILabel()
        label.latex = latex
        label.textColor = NSColor(color)
        label.displayErrorInline = false
        label.fontSize = pointSize
        label.setContentHuggingPriority(.defaultHigh, for: .vertical)
        return label
    }

    func updateNSView(_ nsView: MTMathUILabel, context: Context) {
        nsView.textColor = NSColor(color)
        nsView.latex = latex
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: MTMathUILabel,
        context: Context
    ) -> CGSize? {
        let size = nsView.intrinsicContentSize
        return CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up) + 1)
    }
}

#endif
