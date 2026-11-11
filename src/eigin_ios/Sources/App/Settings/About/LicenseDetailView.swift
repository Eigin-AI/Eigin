import SwiftUI

/// Full license text for one package, with its copyright line and a link to
/// the upstream repository.
struct LicenseDetailView: View {
    let entry: LicenseEntry

    @Environment(\.colors) private var colors
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        SoftEdgeScrollView {
            VStack(alignment: .leading, spacing: Sizing.PageLayout.HeaderGrouping.gap) {
                VStack(alignment: .leading, spacing: Spacing.n4) {
                    if !entry.copyright.isEmpty {
                        Text(entry.copyright)
                            .typography(Typography.titleXS)
                            .foregroundStyle(colors.text.standard.base)
                    }
                    Text(entry.detailProvenance)
                        .typography(Typography.tag)
                        .foregroundStyle(colors.text.standard.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                    if let notice = entry.notice {
                        AppCardSurface {
                            Text(notice)
                                .typography(Typography.tag)
                                .foregroundStyle(colors.text.standard.base)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }

                    ForEach(Array(entry.kind.texts.enumerated()), id: \.offset) { _, text in
                        AppCardSurface {
                            Text(verbatim: text)
                                .typography(Typography.tag)
                                .foregroundStyle(colors.text.standard.base)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }

                    if let repository = entry.repository {
                        Button {
                            openURL(repository)
                        } label: {
                            HStack(spacing: Spacing.n16) {
                                Text(Localized.Settings.About.repository)
                                    .typography(Typography.titleXS)
                                    .foregroundStyle(colors.text.standard.base)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .typography(Typography.miniLabel)
                                    .foregroundStyle(colors.text.standard.muted)
                            }
                            .padding(.horizontal, Spacing.n24)
                            .padding(.vertical, Spacing.n16)
                            .contentShape(Rectangle())
                            .background(colors.surface.standard.alternative)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, Spacing.n16)
            .padding(.top, Spacing.n8)
            .padding(.bottom, Spacing.n32)
        } header: {
            AppNavigationHeader(
                title: entry.name,
                leading: {
                    AppActionButton(
                        icon: Iconography.Functional.Arrow.left,
                        variant: .open,
                        size: .medium,
                        action: { dismiss() }
                    )
                }
            )
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}
