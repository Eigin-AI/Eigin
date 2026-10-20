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

    /// System-font fallback for tokens whose font family isn't installed.
    static func system(size: CGFloat, weight: Font.Weight = .regular) -> FontSpec {
        FontSpec(
            font: .system(size: size, weight: weight),
            uiFont: .systemFont(ofSize: size, weight: uiWeight(weight))
        )
    }

    /// System-font fallback for tokens expressed as a Dynamic Type text style.
    static func system(
        _ style: Font.TextStyle,
        design: Font.Design = .default,
        weight: Font.Weight = .regular
    ) -> FontSpec {
        let base = UIFont.preferredFont(forTextStyle: uiTextStyle(style))
        var descriptor = base.fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: uiWeight(weight)],
        ])
        if let designed = descriptor.withDesign(uiDesign(design)) {
            descriptor = designed
        }
        return FontSpec(
            font: .system(style, design: design, weight: weight),
            // Size 0 keeps the descriptor's own (Dynamic Type scaled) size.
            uiFont: UIFont(descriptor: descriptor, size: 0)
        )
    }

    private static func uiWeight(_ weight: Font.Weight) -> UIFont.Weight {
        switch weight {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }

    private static func uiTextStyle(_ style: Font.TextStyle) -> UIFont.TextStyle {
        switch style {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }

    private static func uiDesign(_ design: Font.Design) -> UIFontDescriptor.SystemDesign {
        switch design {
        case .serif: .serif
        case .rounded: .rounded
        case .monospaced: .monospaced
        default: .default
        }
    }
}

struct TypographyStyle {
    let font: Font
    let uiFont: UIFont
    let textCase: Text.Case?
    let tracking: CGFloat
    /// Full line box in points, with the text centred in it as in Figma and CSS.
    /// Nil keeps the font's natural line height.
    let lineHeight: CGFloat?

    init(
        _ spec: FontSpec,
        textCase: Text.Case? = nil,
        tracking: CGFloat = 0,
        lineHeight: CGFloat? = nil
    ) {
        font = spec.font
        uiFont = spec.uiFont
        self.textCase = textCase
        self.tracking = tracking
        self.lineHeight = lineHeight
    }
}

extension TypographyStyle {
    /// Extra horizontal padding that balances an equal vertical padding. A line's box
    /// carries space above the cap and below the baseline that makes equal padding look
    /// vertically heavier; this is roughly half that difference.
    var opticalInset: CGFloat {
        max(((lineHeight ?? uiFont.lineHeight) - uiFont.capHeight) / 2, 0)
    }

    /// Negative padding that trims the line box to the cap top and last baseline, so
    /// spacing next to the text is the Figma value with no maths. Nil when the style has
    /// no explicit line height (nothing to trim against).
    var capTrim: (top: CGFloat, bottom: CGFloat)? {
        lineHeight.map { uiFont.capTrim(lineHeight: $0) }
    }
}

extension TypographyStyle {
    /// Attributes that draw this style in UIKit text with the same line box as SwiftUI.
    var textAttributes: [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [.font: uiFont]
        if tracking != 0 {
            attributes[.kern] = tracking
        }
        if let lineHeight {
            attributes[.paragraphStyle] = uiFont.paragraphStyle(lineHeight: lineHeight)
        }
        return attributes
    }

    /// Vertical offset that centres the glyphs of a UIKit text view drawn with
    /// `textAttributes` the way SwiftUI and CSS do; negative values move up.
    var textKitShift: CGFloat {
        lineHeight.map { uiFont.textKitShift(lineHeight: $0) } ?? 0
    }
}

extension View {
    func typography(_ style: TypographyStyle) -> some View {
        font(style.font)
            .textCase(style.textCase)
            .tracking(style.tracking)
            .lineBox(style.lineHeight, font: style.uiFont)
    }

    /// File-private on purpose: the trim is only ever applied through `Text.textStyle`.
    /// Chaining it onto untrimmed containers would silently clip layouts against tokens
    /// measured for trimmed boxes.
    @ViewBuilder
    fileprivate func capTrim(_ style: TypographyStyle) -> some View {
        if let trim = style.capTrim {
            padding(.top, -trim.top).padding(.bottom, -trim.bottom)
        } else {
            self
        }
    }

    func navigationTitle(_ title: String, style: TypographyStyle) -> some View {
        navigationTitle(style.textCase == .uppercase ? title.uppercased() : title)
    }
}

extension Text {
    /// Full typography token, trimmed to the cap top and last baseline, so adjacent
    /// spacing is the Figma value with no maths — as on web's `.t-*` classes. Glyphs
    /// taller than the cap and descenders draw outside the trimmed frame, so a parent
    /// that clips (`.clipped()`, `clipShape`) can cut them.
    ///
    /// For buttons, labels, text fields and stacks with icons use `.typography()`
    /// instead: it never trims, so it is safe on containers.
    @MainActor
    func textStyle(_ style: TypographyStyle) -> some View {
        font(style.font)
            .textCase(style.textCase)
            .tracking(style.tracking)
            .lineBox(style.lineHeight, font: style.uiFont)
            .capTrim(style)
    }
}
