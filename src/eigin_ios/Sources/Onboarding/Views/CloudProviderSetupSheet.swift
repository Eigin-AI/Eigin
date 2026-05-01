import SwiftData
import SwiftUI

/// Wraps the provider picker and connection flow inside a sheet.
///
/// When the user selects a preset, switches to the connection screen.
/// If the user already has cloud providers and taps "Continue", calls back
/// with the most recent cloud provider via ``onComplete``.
struct CloudProviderSetupSheet: View {
    let onComplete: (Provider) -> Void
    let onCancel: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Provider.createdAt) private var allProviders: [Provider]

    @State private var selectedPreset: ProviderPreset?

    private var mostRecentCloudProvider: Provider? {
        allProviders.filter { !ProviderPreset.isLocal($0.baseURL) }.last
    }

    var body: some View {
        Group {
            if let preset = selectedPreset {
                OnboardingProviderConnect(
                    preset: preset,
                    onComplete: { provider in
                        onComplete(provider)
                    },
                    onBack: { selectedPreset = nil }
                )
            } else {
                OnboardingProviderSetup(
                    onSelect: { preset in
                        selectedPreset = preset
                    },
                    onContinue: {
                        if let provider = mostRecentCloudProvider {
                            onComplete(provider)
                        } else {
                            onCancel()
                        }
                    }
                )
            }
        }
    }
}
