import SwiftUI
import UIKit

/// Builds the highlight.js stylesheet that colors syntax tokens, so code follows the
/// active palette in the same way every other surface does.
///
/// Selector names are highlight.js class names. Several map to one Eigin token, since
/// the palette is deliberately coarser than highlight.js's token set.
enum CodeHighlightCSS {
    static func stylesheet(for colors: ResolvedColors) -> String {
        let code = colors.code
        return """
        code { color: \(code.plain.cssHex); }
        .hljs-comment,
        .hljs-quote { color: \(code.comment.cssHex); }
        .hljs-keyword,
        .hljs-literal,
        .hljs-doctag,
        .hljs-formula,
        .hljs-selector-tag { color: \(code.keyword.cssHex); font-weight: 600; }
        .hljs-built_in,
        .hljs-type,
        .hljs-tag,
        .hljs-name,
        .hljs-meta,
        .hljs-class .hljs-title,
        .hljs-title.class_ { color: \(code.type.cssHex); }
        .hljs-title,
        .hljs-title.function_,
        .hljs-section { color: \(code.function.cssHex); }
        .hljs-string,
        .hljs-char,
        .hljs-regexp,
        .hljs-meta-string,
        .hljs-template-string { color: \(code.string.cssHex); }
        .hljs-number,
        .hljs-symbol,
        .hljs-bullet { color: \(code.number.cssHex); }
        .hljs-variable,
        .hljs-template-variable,
        .hljs-attr,
        .hljs-attribute,
        .hljs-property,
        .hljs-params,
        .hljs-selector-attr,
        .hljs-selector-class,
        .hljs-selector-id,
        .hljs-selector-pseudo { color: \(code.variable.cssHex); }
        .hljs-link { color: \(code.link.cssHex); }
        .hljs-addition { color: \(code.inserted.cssHex); }
        .hljs-deletion { color: \(code.deleted.cssHex); }
        """
    }
}

private extension Color {
    /// `#RRGGBB` for CSS. Theme colors are plain sRGB values, so this resolves exactly.
    var cssHex: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }
}
