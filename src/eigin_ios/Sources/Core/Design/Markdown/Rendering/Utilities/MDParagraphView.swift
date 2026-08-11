#if canImport(UIKit)
import UIKit

/// Cross-platform paragraph view type. Resolves to `ParagraphUIView` on UIKit and `ParagraphNSView`
/// on AppKit.
typealias MDParagraphView = ParagraphUIView
#elseif canImport(AppKit)
import AppKit

/// Cross-platform paragraph view type. Resolves to `ParagraphUIView` on UIKit and `ParagraphNSView`
/// on AppKit.
typealias MDParagraphView = ParagraphNSView
#endif
