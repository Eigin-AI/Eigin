import Factory
import SwiftUI

/// Connects the agent to inference. Eigin Cloud is the default: choosing it
/// asks consent to share with the relay first, then presents the credits sheet
/// (the relay runs on credits), so nobody pays before they have agreed. Connecting your own
/// provider is secondary. Running offline opens a sheet that kicks off the
/// background model download and returns you here to still pick a provider for
/// this conversation — the cloud always powers onboarding; the local model takes
/// over later once it's ready.
///
/// Provider construction is centralized in the coordinator; this screen reports
/// the user's choice and owns the credits and download sheets.
struct OnboardingInference: View {
    let onUseCloud: () -> Void
    let onConnectOwn: (Provider) -> Void

    @Environment(\.colors) private var colors
    @Injected(\.gemmaModelManager) private var gemmaManager: any GemmaModelManaging
    @Injected(\.aiConsentStore) private var consentStore
    @State private var creditsModel = EiginCreditsModel()

    @State private var showRelayConsent = false
    @State private var showCredits = false
    @State private var showDownload = false
    @State private var showProviderSelect = false
    @State private var showProviderConnect = false
    @State private var selectedMode: ProviderConnectSheetContent.Mode?
    /// Drives the connect sheet's header: the consent step asks its own
    /// question, and setup copy reads as a leftover once the connection is up
    /// (see `ProviderConnectSheetContent.Step`).
    @State private var connectStep = ProviderConnectSheetContent.Step.start

    private var offlineAvailable: Bool {
        gemmaManager.isSupported && offersAction
    }

    /// Whether the sheet offers an action while nothing is under way: a first
    /// download, or another go after a failure or a blocked attempt. Only
    /// supported hardware can retry a blocked attempt.
    private var offersAction: Bool {
        switch gemmaManager.state {
        case .notDownloaded, .failed: true
        case .unavailable: gemmaManager.isSupported
        default: false
        }
    }

    private var offersFirstDownload: Bool {
        gemmaManager.state == .notDownloaded
    }

    private var connectSheetTitle: String {
        switch selectedMode {
        case .preset(let preset, _): preset.name
        case .custom: Localized.Provider.Picker.customProvider
        case nil: ""
        }
    }

    private var connectSheetDescription: String? {
        switch selectedMode {
        case .preset(let preset, _): preset.helpText
        case .custom: Localized.Provider.Setup.Custom.apiRequirement
        case nil: nil
        }
    }

    var body: some View {
        VStack(spacing: Spacing.n16) {
            Spacer()

            if offlineAvailable {
                Button { showDownload = true } label: {
                    Text(Localized.Onboarding.Inference.offlineLink)
                        .typography(Typography.navTab)
                        .foregroundStyle(colors.text.standard.link)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                AppButton(Localized.Onboarding.Inference.useEiginButton) { useEigin() }
                AppButton(Localized.Onboarding.Inference.connectOwnButton, variant: .secondary) {
                    showProviderSelect = true
                }
            }
        }
        .task { await creditsModel.onAppear() }
        .appSheet(
            isPresented: $showRelayConsent,
            title: AIConsentContent.Recipient.relay.title,
            description: AIConsentContent.Recipient.relay.description,
            fitsContent: true
        ) {
            AIConsentContent(
                recipient: .relay,
                onAllow: {
                    consentStore.allow(baseURL: ProviderPreset.relayBaseURL)
                    showRelayConsent = false
                    continueWithEigin()
                },
                onDecline: { showRelayConsent = false }
            )
            .padding(.horizontal, Spacing.n16)
        }
        .appSheet(
            isPresented: $showCredits,
            title: Localized.Provider.Eigin.getCreditsTitle,
            description: Localized.Provider.Eigin.getCreditsDescription,
            fitsContent: true
        ) {
            // Only an actual purchase proceeds; dismissing the sheet stays put.
            GetCreditsSheetContent(model: creditsModel) {
                showCredits = false
                onUseCloud()
            }
        }
        .appSheet(
            isPresented: $showDownload,
            title: Localized.Onboarding.Inference.offlineSheetTitle,
            detents: [.medium],
            fitsContent: true
        ) {
            offlineSheet
        }
        .appSheet(
            isPresented: $showProviderSelect,
            title: Localized.Provider.typeLabel,
            description: Localized.Onboarding.Provider.cloudExplanation,
            detents: [.large]
        ) {
            ProviderSelectSheetContent { selection in
                showProviderSelect = false
                connectStep = .start
                switch selection {
                case .preset(let preset, let method):
                    selectedMode = .preset(preset, method: method)
                case .custom: selectedMode = .custom
                }
                showProviderConnect = true
            }
        }
        .appSheet(
            isPresented: $showProviderConnect,
            title: connectStep.sheetTitle(connectSheetTitle),
            description: connectStep.sheetDescription(connectSheetDescription),
            detents: [.large],
            fitsContent: true
        ) {
            if let mode = selectedMode {
                ProviderConnectSheetContent(
                    mode: mode,
                    onComplete: { provider in
                        showProviderConnect = false
                        selectedMode = nil
                        connectStep = .start
                        onConnectOwn(provider)
                    },
                    onBack: {
                        showProviderConnect = false
                        selectedMode = nil
                        connectStep = .start
                        showProviderSelect = true
                    },
                    onStepChange: { connectStep = $0 }
                )
            }
        }
    }

    /// Uses Eigin Cloud, once sharing with the relay is allowed.
    private func useEigin() {
        if consentStore.needsConsent(baseURL: ProviderPreset.relayBaseURL) {
            showRelayConsent = true
        } else {
            continueWithEigin()
        }
    }

    /// Proceeds straight away when the user already has credits; otherwise
    /// presents the credits sheet to get some first.
    private func continueWithEigin() {
        if creditsModel.totalCredits > 0 {
            onUseCloud()
        } else {
            showCredits = true
        }
    }

    /// The offline download sheet: the Gemma asset row, the pitch, and one
    /// button. Layout never moves — the copy and the button swap in place
    /// once the download starts.
    private var offlineSheet: some View {
        VStack(spacing: Spacing.n24) {
            AssetRow(asset: gemmaManager, showsAction: false)

            Text(
                offersAction
                    ? Localized.Onboarding.Inference.offlineSheetText
                    : Localized.Onboarding.Inference.offlineDownloadingText
            )
            .typography(Typography.description)
            .foregroundStyle(colors.text.standard.muted)
            .fixedSize(horizontal: false, vertical: true)

            if offersAction {
                AppButton(
                    offersFirstDownload
                        ? Localized.Common.Actions.download
                        : Localized.Common.Actions.retry
                ) {
                    Haptics.light()
                    Task { await gemmaManager.download() }
                }
            } else {
                AppButton(Localized.Onboarding.Inference.continueButton) {
                    showDownload = false
                }
            }
        }
        .padding(.horizontal, Spacing.n24)
    }
}

#Preview {
    OnboardingScaffold(
        progress: 0.28,
        title: Localized.Onboarding.Flow.Inference.title,
        text: Localized.Onboarding.Flow.Inference.text
    ) {
        OnboardingInference(onUseCloud: {}, onConnectOwn: { _ in })
    }
    .resolveTheme()
}
