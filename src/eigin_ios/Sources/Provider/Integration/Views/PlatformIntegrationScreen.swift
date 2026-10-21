import Factory
import SwiftUI

/// One integration iOS gives permission for: Apple Health, Apple Calendar,
/// Apple Reminders or Location.
///
/// Like any integration, it is connected or it isn't, so there are no switches
/// here; a tool can still be narrowed in the agent's permissions. What it reads
/// and saves is listed kind by kind, which is the disclosure App Review asks
/// for. iOS owns the permission itself, so a kind iOS reports as off says Not
/// allowed, and the link out is where that changes. Apple Health never says
/// what it lets Eigin read, so only its saves can show as off.
struct PlatformIntegrationScreen: View {
    let integration: Integration

    @Injected(\.integrationManager) private var integrationManager
    @Environment(\.colors) private var colors
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var access: PlatformAccess?
    @State private var showRemoveConfirmation = false

    private var type: IntegrationType? {
        BundledIntegrationType.type(forID: integration.typeID)
    }

    private var source: PlatformAccessSource? {
        type?.authKind.platform
    }

    private var displayName: String {
        type?.displayName ?? integration.typeID
    }

    /// Eigin's page in Settings is where iOS keeps every platform permission.
    private var settings: String {
        Localized.Integrations.Platform.Place.settings
    }

    /// Opens where the permissions are changed.
    @MainActor
    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private var isRefused: Bool {
        access == .refused
    }

    /// Connected, but iOS has never been asked for the access Eigin needs —
    /// e.g. it changed since the person last allowed it. Tools can't ask, so
    /// the screen offers to.
    private var notAsked: Bool {
        access == .notAsked
    }

    private var notAllowed: Set<PlatformDataKind> {
        if case .allowed(let kinds) = access { kinds } else { [] }
    }

    var body: some View {
        AppAnchoredScrollView {
            VStack(spacing: Sizing.PageLayout.gap) {
                AppIdentityHeader(
                    name: displayName,
                    kind: Localized.Integrations.Platform.kindLabel,
                    state: isRefused ? .attention : .connected,
                    status: isRefused
                        ? Localized.Integrations.Platform.notAllowed
                        : Localized.Integration.Screen.Status.connected,
                    icon: type?.brandImage
                )

                // Only when it can't work at all. Tapping it goes where
                // the link goes.
                if isRefused {
                    AppNotice(
                        tone: .warning,
                        title: Localized.Integrations.Platform.Screen.offTitle(
                            displayName,
                            settings
                        ),
                        body: Localized.Integrations.Platform.Screen.offBody(settings),
                        action: { openSettings() }
                    )
                }

                if notAsked {
                    AppNotice(
                        tone: .warning,
                        title: Localized.Integrations.Platform.Screen
                            .notAskedTitle(displayName),
                        body: Localized.Integrations.Platform.Screen.notAskedBody,
                        action: { askAgain() }
                    )
                }

                if let source {
                    kindsGroup(Localized.Integrations.Platform.reads, kinds: source.reads)
                    kindsGroup(Localized.Integrations.Platform.saves, kinds: source.saves)
                }

                AppRowsGroup(
                    footnote: Localized.Integrations.Platform.Screen.changeFootnote(settings),
                    rows: [
                        AppRowSpec(
                            title: Localized.Integrations.Platform.Screen
                                .changeAccess(settings),
                            accessory: .link,
                            action: { openSettings() }
                        ),
                    ]
                )

                AppRowsGroup(rows: [
                    AppRowSpec(
                        title: Localized.Integration.Screen.remove(displayName),
                        accessory: .trash,
                        tone: .destructive,
                        action: { showRemoveConfirmation = true }
                    ),
                ])
            }
            .padding(.horizontal, Spacing.n16)
            .padding(.top, Spacing.n8)
            .padding(.bottom, Spacing.n32)
        } header: {
            AppNavigationHeader(
                title: displayName,
                leading: {
                    AppActionButton(
                        icon: Iconography.Functional.Arrow.left,
                        variant: .open,
                        size: .medium,
                        action: { dismiss() }
                    )
                }
            )
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .alert(
            Localized.Integration.Screen.removeTitle(displayName),
            isPresented: $showRemoveConfirmation
        ) {
            Button(Localized.Integrations.Action.disconnect, role: .destructive) { remove() }
            Button(Localized.Common.Actions.cancel, role: .cancel) {}
        } message: {
            Text(Localized.Integrations.Platform.Screen.removeWarning)
        }
        .task { await refresh() }
        // Coming back from Settings is the usual way access changes.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
    }

    // MARK: - Kinds

    @ViewBuilder
    private func kindsGroup(_ label: String, kinds: [PlatformDataKind]) -> some View {
        if !kinds.isEmpty {
            AppRowsGroup(
                label: label,
                footnote: isLastGroup(kinds) ? offFootnote : nil,
                rows: kinds.map { kind in
                    AppRowSpec(
                        id: kind.id,
                        title: kind.name,
                        value: isRefused || notAllowed.contains(kind)
                            ? Localized.Integrations.Platform.notAllowed
                            : nil,
                        accessory: .none
                    )
                }
            )
        }
    }

    /// Explains the kinds marked Not allowed, and leads into the link that
    /// changes them. The notice says it instead when nothing is allowed.
    private var offFootnote: String? {
        notAllowed.isEmpty ? nil : Localized.Integrations.Platform.Screen.someOff
    }

    private func isLastGroup(_ kinds: [PlatformDataKind]) -> Bool {
        guard let source else { return false }
        return source.saves.isEmpty ? kinds == source.reads : kinds == source.saves
    }

    // MARK: - Actions

    private func refresh() async {
        guard let source else { return }
        access = await source.permission().access()
    }

    /// Shows the iOS prompt the connected integration never got, then
    /// re-reads where it landed.
    private func askAgain() {
        guard let source else { return }
        Task {
            _ = await source.permission().request()
            access = await source.permission().access()
        }
    }

    /// Stops Eigin using it. iOS keeps what it allows; Eigin can't take that back.
    private func remove() {
        integrationManager.disconnect(integration)
        integrationManager.clearSelections(referencing: integration.id, in: modelContext)
        modelContext.delete(integration)
        dismiss()
    }
}

#Preview("Apple Health") {
    NavigationStack {
        PlatformIntegrationScreen(integration: Integration(
            typeID: BundledIntegrationType.appleHealth.id,
            accountLabel: "",
            grantedCapabilities: [Capability.health.rawValue]
        ))
    }
    .previewEnvironment()
}
