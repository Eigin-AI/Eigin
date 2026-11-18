import Factory
import SwiftUI

/// Displays trusted WeatherKit marks and legal information in chat or provider details.
struct WeatherAttributionView: View {
    var showsDetails = false
    @Injected(\.weatherAttributionService) private var service
    @Environment(\.colors) private var colors
    @Environment(\.colorScheme) private var colorScheme
    @State private var attribution: WeatherSourceAttribution?
    @State private var failed = false
    @State private var showingLegal = false

    var body: some View {
        Group {
            if let attribution {
                if showsDetails {
                    details(attribution)
                } else {
                    legalButton(attribution)
                }
            } else if failed {
                VStack(alignment: .leading, spacing: Spacing.n8) {
                    Text(Localized.Weather.Attribution.unavailable)
                        .typography(Typography.note)
                    Button { Task { await load() } } label: {
                        Text(Localized.Weather.Attribution.retry)
                            .frame(minHeight: Sizing.Button.Height.small)
                            .contentShape(Rectangle())
                    }
                }
            } else {
                ProgressView(Localized.Weather.Attribution.loading)
                    .typography(Typography.note)
            }
        }
        .task { await load() }
        .sheet(isPresented: $showingLegal) {
            if let attribution { SafariView(url: attribution.legalURL) }
        }
    }

    private func mark(_ attribution: WeatherSourceAttribution) -> some View {
        // WeatherKit's light mark is for light backgrounds; its dark mark is white.
        let data = colorScheme == .dark ? attribution.darkMark : attribution.lightMark
        return Group {
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 99, height: 18)
                    .accessibilityLabel(Localized.Weather.Attribution.provider)
            }
        }
    }

    private func legalButton(_ attribution: WeatherSourceAttribution) -> some View {
        Button { showingLegal = true } label: {
            VStack(alignment: .leading, spacing: Spacing.n4) {
                mark(attribution)
                Text(Localized.Weather.Attribution.legalLink)
                    .typography(Typography.note)
                    .underline()
                    .foregroundStyle(colors.text.standard.muted)
            }
            .padding(.vertical, Spacing.n8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private func details(_ attribution: WeatherSourceAttribution) -> some View {
        VStack(alignment: .leading, spacing: Sizing.PageLayout.HeaderGrouping.gap) {
            VStack(alignment: .leading, spacing: Spacing.n8) {
                mark(attribution).padding(.bottom, Spacing.n8)
                Text(Localized.Weather.Attribution.provenance)
                    .typography(Typography.tag)
                    .foregroundStyle(colors.text.standard.muted)
            }
            .padding(.horizontal, Spacing.n24)

            VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                AppCardSurface {
                    VStack(alignment: .leading, spacing: Spacing.n16) {
                        Text(Localized.Weather.Attribution.disclosure)
                        Text(Localized.Weather.Attribution.sourcesDisclosure)
                    }
                    .typography(Typography.tag)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                AppCardSurface(padding: 0) {
                    Button { showingLegal = true } label: {
                        AppRow(AppRowSpec(
                            title: Localized.Weather.Attribution.legalLink,
                            description: Localized.Weather.Attribution.legalDescription,
                            accessory: .link
                        ))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @MainActor private func load() async {
        guard attribution == nil else { return }
        failed = false
        do { attribution = try await service.load() }
        catch { failed = true }
    }
}
