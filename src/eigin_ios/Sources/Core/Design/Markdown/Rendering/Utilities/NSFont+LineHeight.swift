#if canImport(AppKit) && !canImport(UIKit)
import AppKit

extension NSFont {
    /// Approximate `UIFont.lineHeight` using font metrics available on AppKit.
    var lineHeight: CGFloat {
        ceil(ascender - descender + leading)
    }
}
#endif
