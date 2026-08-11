#if canImport(UIKit)
import UIKit

/// Cross-platform font type. Resolves to `UIFont` on UIKit platforms and `NSFont` on AppKit
/// platforms.
typealias MDFont = UIFont
#elseif canImport(AppKit)
import AppKit

/// Cross-platform font type. Resolves to `UIFont` on UIKit platforms and `NSFont` on AppKit
/// platforms.
typealias MDFont = NSFont
#endif
