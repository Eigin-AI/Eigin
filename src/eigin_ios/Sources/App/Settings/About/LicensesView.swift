import SwiftUI

/// Settings > About > Licenses: attribution list for every third-party package
/// shipped in the app. Mirrors `LICENSES/eigin_ios.md`; tap a package for
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
        SoftEdgeScrollView {
            VStack(spacing: Sizing.PageLayout.gap) {
                VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                    sectionLabel(Localized.Settings.About.libraries)

                    // One card with dividers. The explicit VStack matters:
                    // AppCardSurface's content is a view builder, so bare children
                    // each get the card background applied individually.
                    AppCardSurface(padding: 0) {
                        VStack(spacing: 0) {
                            NavigationLink {
                                SDKNoticesView()
                                    .hidesTabBar()
                            } label: {
                                if case .success(let catalog) = SDKLicenseCatalog.bundled {
                                    LicenseRow(entry: catalog.sdk)
                                } else {
                                    Text(verbatim: "Eigin SDK")
                                        .typography(Typography.titleXS)
                                        .padding(Spacing.n24)
                                }
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, Spacing.n24)

                            ForEach(
                                Array(entries.enumerated()),
                                id: \.element.id
                            ) { index, entry in
                                NavigationLink {
                                    LicenseDetailView(entry: entry)
                                        .hidesTabBar()
                                } label: {
                                    LicenseRow(entry: entry)
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
                                    LicenseRow(entry: model)
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
        } header: {
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
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .typography(Typography.miniLabel)
            .foregroundStyle(colors.text.standard.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.n8)
    }
}
