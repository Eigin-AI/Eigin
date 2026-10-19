import SwiftUI
import UIKit

/// Line boxes as Figma and CSS draw them: every line is exactly `lineHeight` tall and
/// the glyphs sit centred in it, with half the leftover space above and half below.
extension UIFont {
    /// First baseline, measured from the top of the line box.
    func centredBaseline(lineHeight: CGFloat) -> CGFloat {
        (lineHeight - ascender + descender) / 2 + ascender
    }

    /// Makes every TextKit line exactly `lineHeight` tall. TextKit adds the font's
    /// leading on top of the maximum, so it is taken off here.
    func paragraphStyle(lineHeight: CGFloat) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = lineHeight - leading
        style.maximumLineHeight = lineHeight - leading
        return style
    }

    /// Offset that centres TextKit text set with `paragraphStyle(lineHeight:)`;
    /// negative values move up, because TextKit puts all the spare space above the glyphs.
    func textKitShift(lineHeight: CGFloat) -> CGFloat {
        centredBaseline(lineHeight: lineHeight) - (lineHeight - leading + descender)
    }
}

/// Draws SwiftUI text centred in its line boxes. With an exact line height SwiftUI puts
/// the first baseline at the font size and all the spare space below.
struct CentredLineRenderer: TextRenderer {
    /// Where the first baseline should sit, from the top of the text.
    let baseline: CGFloat

    init(font: UIFont, lineHeight: CGFloat) {
        baseline = font.centredBaseline(lineHeight: lineHeight)
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        guard let first = layout.first else { return }
        context.translateBy(x: 0, y: baseline - first.origin.y)
        for line in layout {
            context.draw(line)
        }
    }
}

extension View {
    /// Lays text out in exact line boxes with the glyphs centred, as Figma and CSS do.
    /// Nil keeps the font's natural line height.
    @ViewBuilder
    func lineBox(_ lineHeight: CGFloat?, font: UIFont) -> some View {
        if let lineHeight {
            self
                .lineHeight(.exact(points: lineHeight))
                .textRenderer(CentredLineRenderer(font: font, lineHeight: lineHeight))
        } else {
            self
        }
    }
}
