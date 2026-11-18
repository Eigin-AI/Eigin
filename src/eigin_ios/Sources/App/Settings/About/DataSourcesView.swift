import SwiftUI

/// Data-provider list alongside the open-source license list in About.
struct DataSourcesView: View {
    var body: some View {
        DataSourceScreen(title: Localized.Settings.About.dataSources) {
            AppCardSurface(padding: 0) {
                NavigationLink {
                    DataSourceScreen(title: Localized.Weather.Attribution.provider) {
                        WeatherAttributionView(showsDetails: true)
                    }
                    .hidesTabBar()
                } label: {
                    AppRow(AppRowSpec(
                        title: Localized.Weather.Attribution.provider,
                        description: Localized.Weather.Attribution.summary
                    ))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Shared navigation and content spacing for provider lists and details.
private struct DataSourceScreen<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @Environment(\.colors) private var colors
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SoftEdgeScrollView {
            VStack(alignment: .leading, spacing: Sizing.PageLayout.gap) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.n16)
                .padding(.top, Spacing.n8)
                .padding(.bottom, Spacing.n32)
        } header: {
            AppNavigationHeader(title: title, leading: {
                AppActionButton(
                    icon: Iconography.Functional.Arrow.left,
                    variant: .open, size: .medium,
                    action: { dismiss() }
                )
            })
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}
