import SwiftUI

/// App-wide spacing scale, providing consistent rhythm across all views.
///
/// Based on a modular scale with a generous, breathing aesthetic.
/// Use the smallest size that gives elements room without feeling cramped.
enum Spacing {
    /// 4pt — Tight inline spacing (e.g. icon to label in a compact row).
    static let xs: CGFloat = 4

    /// 8pt — Related elements within a group (e.g. text lines in a stack).
    static let sm: CGFloat = 8

    /// 16pt — Default spacing between distinct elements.
    static let md: CGFloat = 16

    /// 24pt — Separation between sections or groups of content.
    static let lg: CGFloat = 24

    /// 32pt — Major section breaks or generous padding around content areas.
    static let xl: CGFloat = 32

    /// 48pt — Hero-level breathing room.
    static let xxl: CGFloat = 48
}
