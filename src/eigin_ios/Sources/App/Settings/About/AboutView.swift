import Factory
import SwiftUI

/// Settings > About: app version, legal links and third-party license
/// attributions. App Store Guideline 5.1.1 requires the privacy policy link
/// in an easily accessible place.
struct AboutView: View {
    @Environment(\.colors) private var colors
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let deviceInfo = DefaultDeviceInfoService()

    var body: some View {
        SoftEdgeScrollView {
            VStack(spacing: Sizing.PageLayout.gap) {
                appSection
                legalSection
                creditsSection
            }
            .padding(.horizontal, Spacing.n16)
            .padding(.top, Spacing.n8)
            .padding(.bottom, Spacing.n32)
        } header: {
            AppNavigationHeader(
                title: Localized.Settings.Section.about,
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

    // MARK: - App

    private var appSection: some View {
        // The nav header already says "About"; no section label, like the
        // first group on sibling screens.
        AppCardSurface {
            VStack(alignment: .leading, spacing: Spacing.n8) {
                Text(deviceInfo.appName())
                    .typography(Typography.titleM)
                    .foregroundStyle(colors.text.standard.base)

                Text(versionLine)
                    .typography(Typography.tag)
                    .foregroundStyle(colors.text.standard.muted)
            }
        }
    }

    /// "Version 0.16.0 (42)" when we have a build number, otherwise no
    /// dangling parentheses.
    private var versionLine: String {
        let version = deviceInfo.appVersion()
        let build = deviceInfo.appBuildVersion()
        if build.isEmpty {
            return Localized.Settings.About.appVersionFormat(version)
        }
        return Localized.Settings.About.appVersionBuildFormat(version, build)
    }

    // MARK: - Legal

    private var legalSection: some View {
        VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
            sectionLabel(Localized.Settings.About.legal)

            AppCardSurface(padding: 0) {
                VStack(spacing: 0) {
                    linkRow(
                        Localized.Settings.About.privacyPolicy,
                        url: AppKeys.privacyPolicyURL
                    )

                    Divider().padding(.leading, Spacing.n24)

                    linkRow(
                        Localized.Settings.About.termsOfService,
                        url: AppKeys.termsOfServiceURL
                    )
                }
            }
        }
    }

    private func linkRow(_ title: String, url: URL?) -> some View {
        Button {
            if let url { openURL(url) }
        } label: {
            HStack(spacing: Spacing.n16) {
                Text(title)
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
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
    }

    // MARK: - Credits

    private var creditsSection: some View {
        VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
            sectionLabel(Localized.Settings.About.licenseListTitle)

            AppCardSurface(padding: 0) {
                NavigationLink {
                    LicensesView()
                        .hidesTabBar()
                } label: {
                    HStack(spacing: Spacing.n16) {
                        VStack(alignment: .leading, spacing: Spacing.n4) {
                            Text(Localized.Settings.About.licenseListTitle)
                                .typography(Typography.titleXS)
                                .foregroundStyle(colors.text.standard.base)
                            Text(
                                Localized.Settings.About.licenseCountFormat(
                                    String(LicenseEntry.all.count)
                                )
                            )
                            .typography(Typography.tag)
                            .foregroundStyle(colors.text.standard.muted)
                            .multilineTextAlignment(.leading)
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
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .typography(Typography.miniLabel)
            .foregroundStyle(colors.text.standard.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.n8)
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
    .previewEnvironment()
}
