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

    @State private var displayedState: AssetState = .notDownloaded
    @State private var showCloudSetup = false
    @State private var currentWordIndex = 0

    private let cyclingWords = [
        Localized.Onboarding.ModelSetup.Words.independence,
        Localized.Onboarding.ModelSetup.Words.privacy,
        Localized.Onboarding.ModelSetup.Words.freedom,
        Localized.Onboarding.ModelSetup.Words.ownership,
        Localized.Onboarding.ModelSetup.Words.sovereignty,
    ]

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            stateContent
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(colors.background.ignoresSafeArea())
        .sheet(isPresented: $showCloudSetup) {
            CloudProviderSetupSheet(
                onComplete: { provider in
                    showCloudSetup = false
                    onCloudProviderReady(provider)
                },
                onCancel: { showCloudSetup = false }
            )
        }
        .task {
            displayedState = gemmaManager.state
            gemmaManager.checkAvailability()
            if gemmaManager.state == .downloaded {
                await gemmaManager.compile()
            }
        }
        .onChange(of: gemmaManager.state) { oldState, newState in
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
        VStack(spacing: Spacing.xl) {
            Spacer()

            VStack(spacing: Spacing.xl) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(colors.accent)

                VStack(spacing: Spacing.xs) {
                    Text(Localized.Onboarding.ModelSetup.intro)
                        .font(Typography.title)
                    Text(cyclingWords[currentWordIndex])
                        .font(Typography.largeTitle)
                        .foregroundStyle(colors.accent)
                        .contentTransition(.numericText())
                }
                .foregroundStyle(colors.textPrimary)
                .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: Spacing.lg) {
                Text(Localized.Onboarding.LocalModel.description)
                    .font(Typography.body)
                    .foregroundStyle(colors.textSecondary)
                    .multilineTextAlignment(.center)

                Button {
                    Task { await gemmaManager.download() }
                } label: {
                    Text(Localized.Onboarding.ModelSetup.downloadAction)
                        .font(Typography.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(colors.accent)

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
        VStack(spacing: Spacing.xl) {
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
                        .font(Typography.title)
                        .foregroundStyle(colors.textPrimary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }

            VStack(spacing: Spacing.md) {
                Text(
                    Localized.Onboarding.ModelSetup.downloadStatus
                )
                .font(Typography.body)
                .foregroundStyle(colors.textSecondary)
                .multilineTextAlignment(.center)

                Text(
                    gemmaManager.notifyOnDownloadComplete
                        ? Localized.Onboarding.ModelSetup.notifyConfirmation
                        : Localized.Onboarding.ModelSetup.notifyOffer
                )
                .font(Typography.body)
                .foregroundStyle(colors.textSecondary)
                .multilineTextAlignment(.center)

                Button {
                    Task {
                        let granted = await NotificationPermission.requestIfNeeded()
                        if granted {
                            gemmaManager.notifyOnDownloadComplete = true
                        }
                    }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Text(Localized.Onboarding.ModelSetup.notifyAction)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12))
                    }
                    .font(Typography.callout)
                }
                .foregroundStyle(colors.accent)
                .opacity(gemmaManager.notifyOnDownloadComplete ? 0 : 1)
                .disabled(gemmaManager.notifyOnDownloadComplete)
            }

            Spacer()

            VStack(spacing: Spacing.lg) {
                Button {
                    gemmaManager.cancel()
                } label: {
                    Text(Localized.Common.Actions.cancel)
                        .font(Typography.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(colors.textSecondary)

                cloudLink
            }
        }
    }

    // MARK: - Compiling

    private func compilingView(progress: Double) -> some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            compilingAnimation

            VStack(spacing: Spacing.md) {
                Text(
                    Localized.Status.preparingDevice
                )
                .font(Typography.body)
                .foregroundStyle(colors.textSecondary)
                .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: Spacing.lg) {
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

            VStack(spacing: Spacing.xl) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(colors.accent)

                Text(Localized.Onboarding.ModelSetup.readyStatus)
                    .font(Typography.title)
                    .foregroundStyle(colors.textPrimary)
            }

            Spacer()

            VStack(spacing: Spacing.lg) {
                Button {
                    onReady()
                } label: {
                    Text(Localized.Common.Actions.continue)
                        .font(Typography.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(colors.accent)

                cloudLink
            }
        }
    }

    // MARK: - Failed

    private func failedView(message: String) -> some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: Spacing.xl) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(colors.destructive)

                VStack(spacing: Spacing.sm) {
                    Text(Localized.Onboarding.ModelSetup.errorTitle)
                        .font(Typography.title)
                        .foregroundStyle(colors.textPrimary)
                }
            }

            VStack(spacing: Spacing.md) {
                Button {
                    Task { await gemmaManager.download() }
                } label: {
                    Text(Localized.Common.Actions.retry)
                        .font(Typography.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(colors.accent)

                cloudLink
            }
        }
    }

    private var cloudLink: some View {
        Button {
            showCloudSetup = true
        } label: {
            HStack(spacing: Spacing.xs) {
                Text(Localized.Onboarding.ModelSetup.fallbackAction)
                Image(systemName: "arrow.right")
                    .font(.system(size: 12))
            }
            .font(Typography.callout)
        }
        .foregroundStyle(colors.textSecondary)
    }
}

#Preview {
    OnboardingModelSetup(onReady: {}, onCloudProviderReady: { _ in })
        .previewEnvironment()
}
