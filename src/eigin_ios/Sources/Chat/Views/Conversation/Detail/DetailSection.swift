import SwiftUI

/// A labeled section used in detail sheets.
struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    @Environment(\.colors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(Typography.caption)
                .foregroundStyle(colors.textSecondary)
            content
        }
    }
}
