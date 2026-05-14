import SwiftUI

/// A labeled section used in detail sheets.
struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    @Environment(\.colors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.n8) {
            Text(title)
                .typography(Typography.miniLabel)
                .foregroundStyle(colors.text.standard.muted)
            content
        }
    }
}
