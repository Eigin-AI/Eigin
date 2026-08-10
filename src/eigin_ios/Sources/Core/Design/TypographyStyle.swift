import CoreText
import SwiftUI
import UIKit

/// A font resolved for both SwiftUI and UIKit.
///
/// Generated typography tokens are written as leading-dot expressions
/// (`.custom(…)`, `.featuredFont(…)`), so they resolve against this type rather
/// than `Font`. Carrying the `UIFont` alongside lets UIKit-backed renderers use
/// the same tokens without restating sizes and PostScript names.
struct FontSpec {
    let font: Font
    let uiFont: UIFont

    static func custom(_ name: String, size: CGFloat) -> FontSpec {
        let uiFont = UIFont(name: name, size: size) ?? .systemFont(ofSize: size)
        return FontSpec(font: Font(uiFont), uiFont: uiFont)
    }

    static func featuredFont(name: String, size: CGFloat, features: [FontFeature]) -> FontSpec {
        let uiFont = UIFont.featured(name: name, size: size, features: features)
        return FontSpec(font: Font(uiFont), uiFont: uiFont)
    }

    // Typography tokens whose font family isn't installed fall back to a system
    // font expression. None exist today; add the matching factory here if one appears.
}

struct TypographyStyle {
    let font: Font
    let uiFont: UIFont
    let textCase: Text.Case?
    let tracking: CGFloat
    /// Extra line spacing in points added on top of the font's intrinsic
    /// line height (`lineHeight - fontSize`). Nil when not specified.
    let lineSpacing: CGFloat?

    init(
        _ spec: FontSpec,
        textCase: Text.Case? = nil,
        tracking: CGFloat = 0,
        lineSpacing: CGFloat? = nil
    ) {
        font = spec.font
        uiFont = spec.uiFont
        self.textCase = textCase
        self.tracking = tracking
        self.lineSpacing = lineSpacing
    }
}

extension TypographyStyle {
    /// Extra horizontal padding that balances an equal vertical padding. A line's box
    /// carries space above the cap and below the baseline that makes equal padding look
    /// vertically heavier; this is roughly half that difference.
    var lineBoxInset: CGFloat {
        max((uiFont.lineHeight - uiFont.capHeight) / 2, 0)
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
