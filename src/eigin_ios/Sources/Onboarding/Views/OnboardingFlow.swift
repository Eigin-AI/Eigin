import Factory
import SwiftData
import SwiftUI

/// Coordinates the first-launch onboarding flow.
///
/// The setup screens (welcome, name, priority, inference) share one persistent
/// ``OnboardingScaffold`` so the avatar and its fill stay continuous across
/// transitions. Cloud is the default and always powers the conversation;
/// "use offline" starts a background model download without blocking.
///
/// The conversation and reveal steps still use the previous implementation and
/// are replaced in later stages.
struct OnboardingFlow: View {
    @Environment(\.modelContext) private var modelContext
    @Injected(\.relayClient) private var relayClient

    @AppStorage(StorageKey.onboardingStep) private var stepRaw = OnboardingStep.welcome.rawValue
    @AppStorage(StorageKey.onboardingComplete) private var onboardingComplete = false
    @AppStorage(StorageKey.onboardingUserName) private var userName = ""
    @AppStorage(StorageKey.onboardingPriority) private var priorityRaw = ""
    @AppStorage(StorageKey.onboardingProactivity)
    private var proactivityRaw = ProactivityLevel.balanced.rawValue

    @Query(sort: \Provider.createdAt) private var providers: [Provider]
    @Query private var agents: [Agent]

    @State private var conversationProvider: Provider?
    @State private var conversationModel = ""

    private var step: OnboardingStep {
        OnboardingStep(rawValue: stepRaw) ?? .welcome
    }

    private var priority: OnboardingPriority? {
        OnboardingPriority(rawValue: priorityRaw)
    }

    private var proactivity: ProactivityLevel {
        ProactivityLevel(rawValue: proactivityRaw) ?? .reactive
    }

    var body: some View {
        ZStack {
            if step.isSetupScreen {
                OnboardingScaffold(
                    progress: step.avatarProgress,
                    // Welcome is a moment: the avatar makes a pronounced entrance
                    // at full power with no ring, holds a beat, then speaks. The
                    // ring appears from the next step on.
                    showsProgress: step != .welcome,
                    entrance: step == .welcome,
                    title: speech.title,
                    text: speech.text,
                    titleDelay: step == .welcome ? .milliseconds(500) : .zero
                ) {
                    setupContent
                }
            } else if step == .conversation, let provider = conversationProvider,
                      !conversationModel.isEmpty
            {
                OnboardingChat(
                    provider: provider,
                    model: conversationModel,
                    name: userName,
                    priority: priority,
                    proactivity: proactivity,
                    onComplete: { onboardingComplete = true },
                    onBack: { advanceTo(.inference) }
                )
            }
        }
        .task { validateStep() }
    }

    // MARK: - Setup content

    @ViewBuilder private var setupContent: some View {
        switch step {
        case .welcome:
            OnboardingWelcome(onBegin: { advanceTo(.name) })

        case .name:
            OnboardingNameScreen(name: $userName, onContinue: { advanceTo(.priority) })

        case .priority:
            OnboardingPriorityScreen { selected in
                priorityRaw = selected.rawValue
                advanceTo(.inference)
            }

        case .inference:
            OnboardingInference(
                onUseCloud: { startCloud() },
                onConnectOwn: { provider in startWithProvider(provider) }
            )

        case .initiative:
            OnboardingInitiativeScreen { enabled in chooseInitiative(enabled) }

        case .conversation:
            EmptyView()
        }
    }

    /// Persists the proactivity choice. When background work is enabled, requests
    /// notification permission before advancing so the prompt appears in context.
    private func chooseInitiative(_ enabled: Bool) {
        let level: ProactivityLevel = enabled ? .balanced : .reactive
        proactivityRaw = level.rawValue

        guard enabled else {
            advanceTo(.conversation)
            return
        }
        Task {
            _ = await NotificationPermission.requestIfNeeded()
            advanceTo(.conversation)
        }
    }

    // MARK: - Navigation

    private func advanceTo(_ next: OnboardingStep) {
        stepRaw = next.rawValue
    }

    // MARK: - Agent speech

    /// The line the avatar "speaks" on the current setup step: a faded-in title
    /// and a streamed body. Personalized with the name gathered so far.
    private var speech: (title: String, text: String) {
        let name = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        switch step {
        case .welcome:
            return (
                Localized.Onboarding.Flow.Welcome.title,
                Localized.Onboarding.Flow.Welcome.text
            )
        case .name:
            return (
                Localized.Onboarding.Flow.Name.title,
                Localized.Onboarding.Flow.Name.text
            )
        case .priority:
            let title = name.isEmpty
                ? Localized.Onboarding.Flow.Priority.title
                : Localized.Onboarding.Flow.Priority.titleWithName(name)
            return (title, Localized.Onboarding.Flow.Priority.text)
        case .inference:
            return (
                Localized.Onboarding.Flow.Inference.title,
                Localized.Onboarding.Flow.Inference.text
            )
        case .initiative:
            return (
                Localized.Onboarding.Flow.Initiative.title,
                Localized.Onboarding.Flow.Initiative.text
            )
        case .conversation:
            return ("", "")
        }
    }

    // MARK: - Inference setup

    /// Sets up the Eigin relay as the conversation provider, then advances.
    /// Called after the user has obtained credits.
    private func startCloud() {
        let provider = ensureRelayProvider()
        conversationProvider = provider

        Task { @MainActor in
            if let models = try? await relayClient.models(), !models.isEmpty {
                provider.availableModels = models
                if provider.enabledModels.isEmpty {
                    provider.enabledModels = [KnownModelCatalog.bestModel(from: models) ?? ""]
                        .filter { !$0.isEmpty }
                }
            }
            conversationModel = provider.enabledModels.first
                ?? provider.availableModels.first ?? ""
            advanceTo(.initiative)
        }
    }

    private func startWithProvider(_ provider: Provider) {
        conversationProvider = provider
        conversationModel = provider.enabledModels.first ?? provider.availableModels.first ?? ""
        advanceTo(.initiative)
    }

    /// Returns the existing Eigin relay provider or creates one. Mirrors
    /// `ContentView.ensureEiginProvider`, which does not run during onboarding.
    @discardableResult
    private func ensureRelayProvider() -> Provider {
        if let existing = providers.first(where: { ProviderPreset.isRelay($0.baseURL) }) {
            return existing
        }
        let provider = Provider(name: "Eigin", baseURL: "eigin-relay://")
        modelContext.insert(provider)
        return provider
    }

    // MARK: - Resume

    /// On resume, fall back to an earlier step if required state is missing.
    private func validateStep() {
        if let agent = agents.first, agent.bootstrapComplete {
            onboardingComplete = true
            return
        }

        switch step {
        case .welcome, .name, .priority, .inference, .initiative:
            break
        case .conversation:
            if conversationProvider == nil {
                if let relay = providers.first(where: { ProviderPreset.isRelay($0.baseURL) }) {
                    conversationProvider = relay
                    conversationModel = relay.enabledModels.first
                        ?? relay.availableModels.first ?? ""
                } else {
                    stepRaw = OnboardingStep.inference.rawValue
                }
            }
        }
    }
}
