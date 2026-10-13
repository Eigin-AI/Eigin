import SwiftUI

/// A chat asking the person to connect what a skill needs, while the agent's
/// activation waits on the answer.
///
/// One integration that provides it opens its own connect sheet straight
/// away: what a platform integration reads and saves, or an account's sign-in.
/// Several are offered to pick from first. Either way the answer goes back to
/// the agent: connected and it carries on with the skill, Not now and it
/// carries on without.
struct ConnectCapabilitySheet: View {
    let request: CapabilityRequest
    let onResolved: (CapabilityConnectResult) -> Void

    /// The account picked from the list, connecting over it.
    @State private var picked: IntegrationType?

    var body: some View {
        let providers = request.providers
        if providers.count == 1, let only = providers.first {
            connectSheet(for: only)
        } else {
            chooser(providers)
                .sheet(item: Binding(
                    get: { picked.map(PickedType.init) },
                    set: { picked = $0?.type }
                )) { item in
                    connectSheet(for: item.type, onBack: { picked = nil })
                        .interactiveDismissDisabled()
                }
        }
    }

    @ViewBuilder
    private func connectSheet(for type: IntegrationType, onBack: (() -> Void)? = nil) -> some View {
        if type.authKind.platform != nil {
            ConnectPlatformSheet(
                type: type,
                requestedBy: request.agentName,
                onConnected: { onResolved(.connected) },
                onDeclined: { back(onBack) }
            )
        } else {
            ConnectIntegrationSheet(
                target: .type(type),
                doneLabel: Localized.Common.Actions.continue,
                onConnected: { onResolved(.connected) },
                onCancelled: { back(onBack) }
            )
        }
    }

    /// Closing a connect sheet picked from the list goes back to the list;
    /// closing the only one is Not now.
    private func back(_ onBack: (() -> Void)?) {
        if let onBack { onBack() } else { onResolved(.declined) }
    }

    private func chooser(_ providers: [IntegrationType]) -> some View {
        AppFittedSheet(
            header: {
                AppSheetHeader(
                    title: Localized.Integrations.Chat.chooseTitle(capabilityName),
                    description: Localized.Integrations.Chat.chooseDescription(
                        request.agentName,
                        capabilityName
                    ),
                    onDismiss: { onResolved(.declined) }
                )
            },
            primary: {
                VStack(spacing: Sizing.PageLayout.gap) {
                    AppRowsGroup(rows: providers.map { type in
                        AppRowSpec(
                            id: type.id,
                            title: type.displayName,
                            description: type.description,
                            icon: type.brandImage,
                            action: { picked = type }
                        )
                    })
                    AppButton(Localized.Common.Actions.notNow, variant: .secondary) {
                        onResolved(.declined)
                    }
                }
                .padding(.horizontal, Spacing.n16)
            }
        )
    }

    /// What is being asked for, as one name: "email", "calendar or reminders".
    private var capabilityName: String {
        let names = Capability.allCases
            .filter(request.capabilities.contains)
            .map { $0.displayName.lowercased() }
        return ListFormatter.localizedString(byJoining: names)
    }

    private struct PickedType: Identifiable {
        let type: IntegrationType
        var id: String {
            type.id
        }
    }
}
