import SwiftUI

/// SDK license information and navigable runtime dependency notices.
struct SDKNoticesView: View {
    @Environment(\.colors) private var colors
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SoftEdgeScrollView {
            VStack(spacing: Sizing.PageLayout.gap) {
                switch SDKLicenseCatalog.bundled {
                case .success(let catalog):
                    packageList([catalog.sdk])
                    VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                        Text(Localized.Settings.About.libraries)
                            .typography(Typography.miniLabel)
                            .foregroundStyle(colors.text.standard.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Spacing.n8)
                        packageList(catalog.dependencies)
                    }
                case .failure(let error):
                    Text(error.localizedDescription)
                        .typography(Typography.tag)
                        .foregroundStyle(colors.text.standard.base)
                }
            }
            .padding(.horizontal, Spacing.n16)
            .padding(.top, Spacing.n8)
            .padding(.bottom, Spacing.n32)
        } header: {
            AppNavigationHeader(
                title: "Eigin SDK",
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

    private func packageList(_ entries: [LicenseEntry]) -> some View {
        AppCardSurface(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
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
}
