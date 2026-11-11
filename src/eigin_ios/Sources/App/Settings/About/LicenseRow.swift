import SwiftUI

/// Package name and license summary used in license navigation lists.
struct LicenseRow: View {
    let entry: LicenseEntry
    @Environment(\.colors) private var colors

    var body: some View {
        HStack(spacing: Spacing.n16) {
            VStack(alignment: .leading, spacing: Spacing.n4) {
                Text(entry.name)
                    .typography(Typography.titleXS)
                    .foregroundStyle(colors.text.standard.base)
                Text(entry.rowSubtitle)
                    .typography(Typography.tag)
                    .foregroundStyle(colors.text.standard.muted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .typography(Typography.miniLabel)
                .foregroundStyle(colors.text.standard.muted)
        }
        .padding(.horizontal, Spacing.n24)
        .padding(.vertical, Spacing.n16)
        .contentShape(Rectangle())
    }
}
