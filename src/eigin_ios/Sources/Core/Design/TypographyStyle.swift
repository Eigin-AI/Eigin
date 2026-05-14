import SwiftUI

struct TypographyStyle {
    let font: Font
    let textCase: Text.Case?
    let tracking: CGFloat
    /// Additional line spacing in points (lineHeight - fontSize). Nil when not specified.
    let lineSpacing: CGFloat?

    init(
        _ font: Font,
        textCase: Text.Case? = nil,
        tracking: CGFloat = 0,
        lineSpacing: CGFloat? = nil
    ) {
        self.font = font
        self.textCase = textCase
        self.tracking = tracking
        self.lineSpacing = lineSpacing
    }
}

extension View {
    func typography(_ style: TypographyStyle) -> some View {
        let base = font(style.font)
            .textCase(style.textCase)
            .tracking(style.tracking)
        if let spacing = style.lineSpacing {
            return AnyView(base.lineSpacing(max(0, spacing)))
        }
        return AnyView(base)
    }

    func navigationTitle(_ title: String, style: TypographyStyle) -> some View {
        navigationTitle(style.textCase == .uppercase ? title.uppercased() : title)
    }
}
