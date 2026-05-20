import SwiftUI

/// Download screen shown when the local AI model is not yet available.
///
/// Gives the user two paths: download the on-device model or connect a cloud provider.
/// Auto-advances via `onReady` once the model is downloaded and ready.
struct OnboardingModelSetup: View {
    @Environment(\.colors) private var colors
    @Bindable private var gemmaManager = GemmaModelManager.shared

    let onReady: () -> Void
    let onCloudProviderReady: (Provider) -> Void

    /// When non-nil, forces the view into this state for previews.
    /// Always `nil` in production.
    let previewState: AssetState?

    @State private var displayedState: AssetState

    init(
        onReady: @escaping () -> Void,
        onCloudProviderReady: @escaping (Provider) -> Void,
        previewState: AssetState? = nil
    ) {
        self.onReady = onReady
        self.onCloudProviderReady = onCloudProviderReady
        self.previewState = previewState
        _displayedState = State(initialValue: previewState ?? .notDownloaded)
    }

    @State private var showCloudSetup = false
    @State private var showCloudConnect = false
    @State private var selectedPreset: ProviderPreset?
    @State private var currentWordIndex = 0

    private let cyclingWords = [
        Localized.Onboarding.ModelSetup.Words.independence,
        Localized.Onboarding.ModelSetup.Words.privacy,
        Localized.Onboarding.ModelSetup.Words.freedom,
        Localized.Onboarding.ModelSetup.Words.ownership,
        Localized.Onboarding.ModelSetup.Words.sovereignty,
    ]

    var body: some View {
        VStack(spacing: Spacing.n32) {
            Spacer()

            stateContent
        }
        .padding(.horizontal, Spacing.n24)
        .padding(.bottom, Spacing.n32)
        .frame(maxWidth: .infinity)
        .background(colors.surface.standard.base.ignoresSafeArea())
        .appSheet(
            isPresented: $showCloudSetup,
            title: Localized.Provider.typeLabel,
            description: Localized.Onboarding.Provider.cloudExplanation,
            detents: [.large]
        ) {
            ProviderSelectSheetContent { preset in
                showCloudSetup = false
                selectedPreset = preset
                showCloudConnect = true
            }
        }
        .appSheet(
            isPresented: $showCloudConnect,
            title: selectedPreset?.name ?? "",
            description: selectedPreset?.helpText,
            detents: [.large]
        ) {
            if let preset = selectedPreset {
                ProviderConnectSheetContent(
                    preset: preset,
                    onComplete: { provider in
                        showCloudConnect = false
                        selectedPreset = nil
                        onCloudProviderReady(provider)
                    },
                    onBack: {
                        showCloudConnect = false
                        selectedPreset = nil
                        showCloudSetup = true
                    }
                )
            }
        }
        .task {
            if let previewState {
                displayedState = previewState
                return
            }
            displayedState = gemmaManager.state
            gemmaManager.checkAvailability()
            if gemmaManager.state == .downloaded {
                await gemmaManager.compile()
            }
        }
        .onChange(of: gemmaManager.state) { oldState, newState in
            guard previewState == nil else { return }
            withAnimation(.easeInOut(duration: Animations.normal)) {
                displayedState = newState
            }
            if newState == .downloaded {
                Task { await gemmaManager.compile() }
            }
            if newState == .ready, oldState.isCompiling || oldState == .downloaded {
                onReady()
            }
        }
    }

    // MARK: - State Content

    @ViewBuilder
    private var stateContent: some View {
        switch displayedState {
        case .notDownloaded:
            notDownloadedView

        case .downloading(let progress):
            downloadingView(progress: progress)

        case .downloaded:
            compilingView(progress: 0)

        case .compiling(let progress):
            compilingView(progress: progress)

        case .ready:
            readyView

        case .failed(let message):
            failedView(message: message)
        }
    }

    // MARK: - Not Downloaded

    private var notDownloadedView: some View {
        VStack(spacing: Spacing.n32) {
            Spacer()

            VStack(spacing: Spacing.n32) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(colors.accent)

                VStack(spacing: Spacing.n4) {
                    Text(Localized.Onboarding.ModelSetup.intro)
                        .typography(Typography.titleM)
                    Text(cyclingWords[currentWordIndex])
                        .typography(Typography.titleXl)
                        .foregroundStyle(colors.accent)
                        .contentTransition(.numericText())
                }
                .foregroundStyle(colors.text.standard.base)
                .multilineTextAlignment(.center)
            }

            Spacer()

            Text(Localized.Onboarding.LocalModel.description)
                .typography(Typography.body)
                .foregroundStyle(colors.text.standard.muted)
                .multilineTextAlignment(.center)

            VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                AppButton(Localized.Onboarding.ModelSetup.downloadAction) {
                    Task { await gemmaManager.download() }
                }

                cloudLink
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                withAnimation(.easeInOut(duration: 0.3)) {
                    currentWordIndex = (currentWordIndex + 1) % cyclingWords.count
                }
            }
        }
    }

    // MARK: - Downloading

    private func downloadingView(progress: Double) -> some View {
        VStack(spacing: Spacing.n32) {
            Spacer()

            ZStack {
                CircularProgressView(
                    progress: progress,
                    size: 150,
                    lineWidth: 8,
                    accentColor: colors.accent
                )

                VStack(spacing: 4) {
                    Text(verbatim: "\(Int(progress * 100))%")
                        .typography(Typography.titleM)
                        .foregroundStyle(colors.text.standard.base)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }

            VStack(spacing: Spacing.n16) {
                Text(
                    Localized.Onboarding.ModelSetup.downloadStatus
                )
                .typography(Typography.body)
                .foregroundStyle(colors.text.standard.muted)
                .multilineTextAlignment(.center)

                Text(
                    gemmaManager.notifyOnDownloadComplete
                        ? Localized.Onboarding.ModelSetup.notifyConfirmation
                        : Localized.Onboarding.ModelSetup.notifyOffer
                )
                .typography(Typography.body)
                .foregroundStyle(colors.text.standard.muted)
                .multilineTextAlignment(.center)

                Button {
                    Task {
                        let granted = await NotificationPermission.requestIfNeeded()
                        if granted {
                            gemmaManager.notifyOnDownloadComplete = true
                        }
                    }
                } label: {
                    HStack(spacing: Spacing.n4) {
                        Text(Localized.Onboarding.ModelSetup.notifyAction)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12))
                    }
                    .typography(Typography.navTab)
                }
                .foregroundStyle(colors.accent)
                .opacity(gemmaManager.notifyOnDownloadComplete ? 0 : 1)
                .disabled(gemmaManager.notifyOnDownloadComplete)
            }

            Spacer()

            VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                AppButton(Localized.Common.Actions.cancel) {
                    gemmaManager.cancel()
                }

                cloudLink
            }
        }
    }

    // MARK: - Compiling

    private func compilingView(progress: Double) -> some View {
        VStack(spacing: Spacing.n32) {
            Spacer()

            compilingAnimation

            VStack(spacing: Spacing.n16) {
                Text(
                    Localized.Status.preparingDevice
                )
                .typography(Typography.body)
                .foregroundStyle(colors.text.standard.muted)
                .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: Spacing.n24) {
                cloudLink
            }
        }
    }

    private var compilingAnimation: some View {
        Image(systemName: "rectangle.3.group")
            .font(.system(size: 56))
            .foregroundStyle(colors.accent)
            .symbolEffect(.breathe, options: .repeating)
    }

    // MARK: - Ready

    private var readyView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: Spacing.n32) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(colors.accent)

                Text(Localized.Onboarding.ModelSetup.readyStatus)
                    .typography(Typography.titleM)
                    .foregroundStyle(colors.text.standard.base)
            }

            Spacer()

            VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                AppButton(Localized.Common.Actions.continue) {
                    onReady()
                }

                cloudLink
            }
        }
    }

    // MARK: - Failed

    private func failedView(message: String) -> some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: Spacing.n32) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(colors.text.standard.error)

                VStack(spacing: Spacing.n8) {
                    Text(Localized.Onboarding.ModelSetup.errorTitle)
                        .typography(Typography.titleM)
                        .foregroundStyle(colors.text.standard.base)
                }
            }

            Spacer()

            VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                AppButton(Localized.Common.Actions.retry) {
                    Task { await gemmaManager.download() }
                }

                cloudLink
            }
        }
    }

    private var cloudLink: some View {
        AppButton(Localized.Onboarding.ModelSetup.fallbackAction, variant: .secondary) {
            showCloudSetup = true
        }
    }
}

#Preview("Not Downloaded") {
    OnboardingModelSetup(
        onReady: {},
        onCloudProviderReady: { _ in }
    )
    .previewEnvironment()
}

#Preview("Downloading – 35%") {
    OnboardingModelSetup(
        onReady: {},
        onCloudProviderReady: { _ in },
        previewState: .downloading(fractionCompleted: 0.35)
    )
    .previewEnvironment()
}

#Preview("Downloading – 90%") {
    OnboardingModelSetup(
        onReady: {},
        onCloudProviderReady: { _ in },
        previewState: .downloading(fractionCompleted: 0.90)
    )
    .previewEnvironment()
}

#Preview("Compiling") {
    OnboardingModelSetup(
        onReady: {},
        onCloudProviderReady: { _ in },
        previewState: .compiling(fractionCompleted: 0)
    )
    .previewEnvironment()
}

#Preview("Ready") {
    OnboardingModelSetup(
        onReady: {},
        onCloudProviderReady: { _ in },
        previewState: .ready
    )
    .previewEnvironment()
}

#Preview("Failed") {
    OnboardingModelSetup(
        onReady: {},
        onCloudProviderReady: { _ in },
        previewState: .failed("Network connection lost. Please try again.")
    )
    .previewEnvironment()
}
