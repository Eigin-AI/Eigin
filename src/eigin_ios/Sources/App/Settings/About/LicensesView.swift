import SwiftUI

/// Settings > About > Licenses: attribution list for every third-party package
/// shipped in the app. Mirrors `LICENSES/swift-packages.md`; tap a package for
/// its full license text (App Store Guideline 5.2.1).
struct LicensesView: View {
    @Environment(\.colors) private var colors
    @Environment(\.dismiss) private var dismiss

    private var entries: [LicenseEntry] {
        LicenseEntry.all
    }

    private var models: [LicenseEntry] {
        LicenseEntry.models
    }

    var body: some View {
        VStack(spacing: 0) {
            AppNavigationHeader(
                title: Localized.Settings.About.licenseListTitle,
                leading: {
                    AppActionButton(
                        icon: Iconography.Functional.Arrow.left,
                        variant: .open,
                        size: .medium,
                        action: { dismiss() }
                    )
                }
            )

            ScrollView {
                VStack(spacing: Sizing.PageLayout.gap) {
                    VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                        sectionLabel(Localized.Settings.About.libraries)

                        // One card with dividers. The explicit VStack matters:
                        // AppCardSurface's content is a view builder, so bare children
                        // each get the card background applied individually.
                        AppCardSurface(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(
                                    Array(entries.enumerated()),
                                    id: \.element.id
                                ) { index, entry in
                                    NavigationLink {
                                        LicenseDetailView(entry: entry)
                                            .hidesTabBar()
                                    } label: {
                                        licenseRow(entry)
                                    }
                                    .buttonStyle(.plain)

                                    if index < entries.count - 1 {
                                        Divider().padding(.leading, Spacing.n24)
                                    }
                                }
                            }
                        }
                    }

                    VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                        sectionLabel(Localized.Settings.About.models)

                        AppCardSurface(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(
                                    Array(models.enumerated()),
                                    id: \.element.id
                                ) { index, model in
                                    NavigationLink {
                                        LicenseDetailView(entry: model)
                                            .hidesTabBar()
                                    } label: {
                                        licenseRow(model)
                                    }
                                    .buttonStyle(.plain)

                                    if index < models.count - 1 {
                                        Divider()
                                            .padding(.leading, Spacing.n24)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Spacing.n16)
                .padding(.top, Spacing.n8)
                .padding(.bottom, Spacing.n32)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func licenseRow(_ entry: LicenseEntry) -> some View {
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

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .typography(Typography.miniLabel)
            .foregroundStyle(colors.text.standard.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.n8)
    }
}

/// Full license text for one package, with its copyright line and a link to
/// the upstream repository.
private struct LicenseDetailView: View {
    let entry: LicenseEntry

    @Environment(\.colors) private var colors
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
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

            ScrollView {
                VStack(alignment: .leading, spacing: Sizing.PageLayout.HeaderGrouping.gap) {
                    VStack(alignment: .leading, spacing: Spacing.n4) {
                        Text(entry.copyright)
                            .typography(Typography.titleXS)
                            .foregroundStyle(colors.text.standard.base)
                        Text(entry.detailProvenance)
                            .typography(Typography.tag)
                            .foregroundStyle(colors.text.standard.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                        AppCardSurface {
                            Text(entry.kind.licenseText())
                                .typography(Typography.tag)
                                .foregroundStyle(colors.text.standard.base)
                                .multilineTextAlignment(.leading)
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
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}
