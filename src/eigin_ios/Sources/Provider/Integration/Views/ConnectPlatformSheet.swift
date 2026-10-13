import Factory
import SwiftUI

/// Connecting an integration iOS gives permission for, from wherever it was
/// asked for: the catalogue, or the agent in a chat.
///
/// It says what Eigin will read and save before iOS asks, because the system
/// prompt names the data but never says why. Then it steps aside: the
/// permission is iOS's, so the sheet waits for it rather than repeating it.
/// From a chat it also names who is asking and offers Not now, and its last
/// step hands back to the agent, which is waiting on the answer.
struct ConnectPlatformSheet: View {
    let type: IntegrationType
    /// The agent asking, when a chat opened this rather than the person.
    var requestedBy: String?
    var onConnected: () -> Void = {}
    /// Not now, or closing before connecting.
    var onDeclined: () -> Void = {}

    private enum Step {
        case disclosure
        case waiting
        case refused
        case done
    }

    @Environment(\.modelContext) private var modelContext
    @Injected(\.integrationManager) private var integrationManager

    @State private var step: Step = .disclosure

    private var source: PlatformAccessSource? {
        type.authKind.platform
    }

    var body: some View {
        AppFittedSheet(
            header: {
                AppSheetHeader(
                    title: step == .done
                        ? Localized.Integration.Connect.connectedTitle
                        : Localized.Integrations.Platform.Connect.title(type.displayName),
                    description: step == .disclosure ? description : nil,
                    onDismiss: { step == .done ? onConnected() : onDeclined() }
                )
            },
            primary: {
                flow
                    .padding(.horizontal, Spacing.n16)
            }
        )
        .task { await startOnRefusedIfNeeded() }
    }

    private var description: String {
        requestedBy.map {
            Localized.Integrations.Platform.Connect.requestedDescription($0, type.displayName)
        } ?? Localized.Integrations.Platform.Connect.description
    }

    @ViewBuilder
    private var flow: some View {
        switch step {
        case .disclosure: disclosureStep
        case .waiting: waitingStep
        case .refused: refusedStep
        case .done: doneStep
        }
    }

    // MARK: - Steps

    private var disclosureStep: some View {
        VStack(spacing: Sizing.PageLayout.gap) {
            // Everything it will ask for, in a line or two above the button.
            AppRowsGroup(rows: uses.map { use in
                AppRowSpec(
                    id: use.title,
                    title: use.title,
                    description: PlatformDataKind.listed(use.kinds),
                    accessory: .none
                )
            })

            VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                AppButton(Localized.Common.Actions.continue) { connect() }
                if requestedBy != nil {
                    AppButton(Localized.Common.Actions.notNow, variant: .secondary) {
                        onDeclined()
                    }
                }
            }
        }
    }

    private var waitingStep: some View {
        AppNotice(
            tone: .info,
            title: Localized.Integration.Connect.Working.waitingTitle,
            body: Localized.Integrations.Platform.Connect.waitingBody(
                source?.asker ?? "iOS"
            )
        )
    }

    /// iOS asks once. After a no, the only way back is Settings, so the sheet
    /// says so rather than offering to ask again.
    private var refusedStep: some View {
        VStack(spacing: Sizing.PageLayout.gap) {
            AppNotice(
                tone: .warning,
                title: Localized.Integrations.Platform.Connect.refusedTitle(type.displayName),
                body: Localized.Integrations.Platform.Connect.refusedBody(
                    Localized.Integrations.Platform.Place.settings
                )
            )
            AppButton(Localized.Common.Actions.openItem(
                Localized.Integrations.Platform.Place.settings
            )) { openSettings() }
        }
    }

    /// Opens where the permissions are changed.
    @MainActor
    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private var doneStep: some View {
        VStack(spacing: Sizing.PageLayout.gap) {
            AppIdentityHeader(
                name: type.displayName,
                kind: Localized.Integrations.Platform.kindLabel,
                state: .connected,
                status: Localized.Integration.Connect.Status.connectedLabel,
                icon: type.brandImage
            )
            AppButton(
                requestedBy == nil
                    ? Localized.Common.Actions.done
                    : Localized.Common.Actions.continue
            ) {
                onConnected()
            }
        }
    }

    // MARK: - What it uses

    /// Reading and saving the same thing is one line, not two that echo.
    private var uses: [(title: String, kinds: [PlatformDataKind])] {
        guard let source else { return [] }
        let readNames = source.reads.map(\.name)
        if !source.saves.isEmpty, readNames == source.saves.map(\.name) {
            return [(Localized.Integrations.Platform.readsAndSaves, source.reads)]
        }
        return [
            (Localized.Integrations.Platform.reads, source.reads),
            (Localized.Integrations.Platform.saves, source.saves),
        ].filter { !$0.kinds.isEmpty }
    }

    // MARK: - Connect

    private func connect() {
        guard let source else { return }
        step = .waiting
        Task {
            switch await source.permission().request() {
            case .allowed:
                integrationManager.connectPlatform(type, in: modelContext)
                Haptics.success()
                step = .done
            case .refused:
                step = .refused
            case .notAsked:
                step = .disclosure
            }
        }
    }

    /// When iOS has already said no, there is nothing to disclose: only
    /// Settings can change it.
    private func startOnRefusedIfNeeded() async {
        guard let source, await source.permission().access() == .refused else { return }
        step = .refused
    }
}

#Preview("Apple Health") {
    ConnectPlatformSheet(type: BundledIntegrationType.appleHealth)
        .previewEnvironment()
}

#Preview("From a chat") {
    ConnectPlatformSheet(type: BundledIntegrationType.appleCalendar, requestedBy: "Wren")
        .previewEnvironment()
}
