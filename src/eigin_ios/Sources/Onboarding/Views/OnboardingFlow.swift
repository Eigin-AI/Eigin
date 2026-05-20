import SwiftData
import SwiftUI

struct OnboardingFlow: View {
    @Environment(\.colors) private var colors
    @Environment(\.modelContext) private var modelContext
    @AppStorage(StorageKey.onboardingStep) private var stepRaw = OnboardingStep.welcome.rawValue
    @AppStorage(StorageKey.onboardingComplete) private var onboardingComplete = false

    @Query(sort: \Provider.createdAt) private var providers: [Provider]
    @Query private var agents: [Agent]

    @State private var onboardingProvider: Provider?
    @State private var conversationProvider: Provider?
    @State private var conversationModel: String = ""
    @State private var revealAgent: Agent?
    @State private var revealHeroText: String = ""
    @State private var revealPriority: OnboardingPriority?
    @State private var revealUsedCloudProvider: Bool = false
    @State private var showProviderSetup = false
    @State private var showProviderConnect = false
    @State private var selectedPreset: ProviderPreset?

    private var step: OnboardingStep {
        OnboardingStep(rawValue: stepRaw) ?? .welcome
    }

    var body: some View {
        ZStack {
            switch step {
            case .welcome:
                OnboardingWelcome {
                    let provider = getOrCreateLocalProvider()
                    conversationProvider = provider
                    conversationModel = "gemma-4-e2b"
                    if GemmaModelManager.shared.isReady {
                        advanceTo(.conversation)
                    } else {
                        advanceTo(.modelSetup)
                    }
                }

            case .modelSetup:
                OnboardingModelSetup(
                    onReady: {
                        let provider = getOrCreateLocalProvider()
                        conversationProvider = provider
                        conversationModel = "gemma-4-e2b"
                        advanceTo(.conversation)
                    },
                    onCloudProviderReady: { provider in
                        onboardingProvider = provider
                        conversationProvider = provider
                        conversationModel = provider.enabledModels.first
                            ?? provider.availableModels.first ?? ""
                        advanceTo(.conversation)
                    }
                )

            case .conversation:
                if let provider = conversationProvider, !conversationModel.isEmpty {
                    OnboardingChat(
                        provider: provider,
                        model: conversationModel,
                        onReveal: { agent, heroText, priority in
                            revealAgent = agent
                            revealHeroText = heroText
                            revealPriority = priority
                            revealUsedCloudProvider = !ProviderPreset
                                .isLocal(conversationProvider?.baseURL ?? "")
                            advanceTo(.reveal)
                        },
                        onBack: { advanceTo(.modelSetup) }
                    )
                }

            case .reveal:
                if let agent = revealAgent {
                    OnboardingReveal(
                        agent: agent,
                        heroText: revealHeroText,
                        priority: revealPriority,
                        showUpgradePitch: !revealUsedCloudProvider,
                        onConnectCloud: { showProviderSetup = true },
                        onStayLocal: { onboardingComplete = true }
                    )
                    .appSheet(
                        isPresented: $showProviderSetup,
                        title: Localized.Provider.typeLabel,
                        description: Localized.Onboarding.Provider.cloudExplanation,
                        detents: [.large]
                    ) {
                        ProviderSelectSheetContent { preset in
                            showProviderSetup = false
                            selectedPreset = preset
                            showProviderConnect = true
                        }
                    }
                    .appSheet(
                        isPresented: $showProviderConnect,
                        title: selectedPreset?.name ?? "",
                        description: selectedPreset?.helpText,
                        detents: [.large]
                    ) {
                        if let preset = selectedPreset {
                            ProviderConnectSheetContent(
                                preset: preset,
                                onComplete: { provider in
                                    showProviderConnect = false
                                    selectedPreset = nil

                                    revealAgent?.providerID = provider.id
                                    revealAgent?.model = provider.enabledModels.first
                                        ?? provider.availableModels.first
                                        ?? revealAgent?.model ?? ""
                                    try? modelContext.save()

                                    onboardingComplete = true
                                },
                                onBack: {
                                    showProviderConnect = false
                                    selectedPreset = nil
                                    showProviderSetup = true
                                }
                            )
                        }
                    }
                }
            }
        }
        .transition(.opacity)
        .animation(Animations.gentle, value: stepRaw)
        .background(colors.surface.standard.base.ignoresSafeArea())
        .task {
            validateStep()
        }
    }

    // MARK: - Navigation

    private func advanceTo(_ next: OnboardingStep) {
        stepRaw = next.rawValue
    }

    /// The provider created during onboarding, falling back to the most recent one in SwiftData.
    private var resolvedProvider: Provider? {
        onboardingProvider ?? providers.last
    }

    /// Get an existing local provider or create one.
    @discardableResult
    private func getOrCreateLocalProvider() -> Provider {
        if let existing = providers.first(where: { $0.baseURL == "local://" }) {
            return existing
        }
        let provider = Provider(name: Localized.Provider.onDevice, baseURL: "local://")
        provider.availableModels = ["gemma-4-e2b"]
        provider.enabledModels = ["gemma-4-e2b"]
        modelContext.insert(provider)
        return provider
    }

    /// On resume, fall back to an earlier step if the required state is missing.
    private func validateStep() {
        switch step {
        case .welcome, .modelSetup:
            break
        case .conversation:
            if conversationProvider == nil {
                if let local = providers.first(where: { $0.baseURL == "local://" }) {
                    conversationProvider = local
                    conversationModel = "gemma-4-e2b"
                } else if let cloud = resolvedProvider {
                    conversationProvider = cloud
                    conversationModel = cloud.enabledModels.first
                        ?? cloud.availableModels.first ?? ""
                } else {
                    stepRaw = OnboardingStep.welcome.rawValue
                }
            }
        case .reveal:
            if revealAgent == nil {
                stepRaw = OnboardingStep.conversation.rawValue
            }
        }

        if let agent = agents.first, agent.bootstrapComplete {
            onboardingComplete = true
        }
    }
}
