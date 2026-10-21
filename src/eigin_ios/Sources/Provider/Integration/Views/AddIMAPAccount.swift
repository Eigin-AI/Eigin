import Factory
import SwiftData
import SwiftUI

/// Sheet for connecting an IMAP/SMTP email account: collect server settings,
/// verify the connection, then save. Presented from ``ConnectIntegrationSheet`` when
/// ``IntegrationScreen`` to reconnect an existing account in place. Adding a
/// new account runs through ``ConnectIntegrationSheet``; this sheet owns the
/// long form either way.
struct AddIMAPAccount: View {
    /// Called after the integration is saved, so the presenting
    /// ``ConnectIntegrationSheet`` sheet can dismiss itself too.
    var onConnected: () -> Void = {}

    /// The existing integration when this sheet runs as an in-place reconnect
    /// — the new credentials are saved under its id and its row is updated
    /// instead of inserting a new one. Pre-fills the stored settings with the
    /// password blank, so the user consciously re-enters it (a stale one would
    /// only re-fail the verify step).
    var existing: Integration?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colors) private var colors
    @Injected(\.integrationHealthMonitor) private var healthMonitor
    @Injected(\.imapCredentialStore) private var credentialStore

    @State private var emailAddress = ""
    @State private var password = ""
    @State private var imapHost = ""
    @State private var imapPort = String(IMAPAccountSettings.defaultIMAPPort)
    @State private var imapUsername = ""
    @State private var smtpHost = ""
    @State private var smtpPort = String(IMAPAccountSettings.defaultSMTPPort)
    @State private var smtpUsername = ""
    @State private var phase: Phase = .editing

    private var isFormValid: Bool {
        !trimmed(emailAddress).isEmpty
            && !trimmed(password).isEmpty
            && !trimmed(imapHost).isEmpty
            && !trimmed(smtpHost).isEmpty
            && Int(trimmed(imapPort)) != nil
            && Int(trimmed(smtpPort)) != nil
    }

    var body: some View {
        SoftEdgeScrollView {
            VStack(spacing: Sizing.PageLayout.gap) {
                accountFields
                imapFields
                smtpFields

                if case .error(let message) = phase {
                    AppCardSurface {
                        VStack(alignment: .leading, spacing: Spacing.n8) {
                            Label(
                                Localized.Errors.Connection.title,
                                systemImage: "exclamationmark.triangle"
                            )
                            .typography(Typography.titleXS)
                            .foregroundStyle(colors.text.standard.error)
                            Text(message)
                                .typography(Typography.tag)
                                .foregroundStyle(colors.text.standard.muted)
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.n16)
            .padding(.top, Spacing.n8)
            .padding(.bottom, Spacing.n32)
        } header: {
            AppNavigationHeader(
                title: Localized.Integrations.Imap.displayName,
                leading: {
                    AppActionButton(
                        icon: Image(systemName: "xmark"),
                        variant: .open,
                        size: .medium,
                        action: { dismiss() }
                    )
                },
                trailing: { trailingAction }
            )
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .onAppear { prefillFromExisting() }
    }

    /// In reconnect mode, seeds the form from the stored settings — everything
    /// except the password, which stays blank so it's consciously re-entered.
    private func prefillFromExisting() {
        guard phase == .editing, let existing,
              let settings = credentialStore.read(for: existing.id)
        else { return }
        emailAddress = settings.emailAddress
        imapHost = settings.imapHost
        imapPort = String(settings.imapPort)
        imapUsername = settings.imapUsername
        smtpHost = settings.smtpHost
        smtpPort = String(settings.smtpPort)
        smtpUsername = settings.smtpUsername
    }

    @ViewBuilder
    private var trailingAction: some View {
        if phase == .verifying {
            ProgressView().padding(.trailing, Spacing.n4)
        } else {
            AppActionButton(
                icon: Image(systemName: "arrow.right"),
                variant: .open,
                size: .medium,
                action: { connect() }
            )
            .disabled(!isFormValid)
        }
    }

    private var accountFields: some View {
        VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
            sectionLabel(Localized.Integrations.Imap.accountSection)
            AppTextInput(label: Localized.Integrations.Imap.emailField, text: $emailAddress)
            AppTextInput(
                label: Localized.Integrations.Imap.passwordField,
                text: $password,
                isSecure: true
            )
            Text(Localized.Integrations.Imap.passwordHint)
                .typography(Typography.tag)
                .foregroundStyle(colors.text.standard.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.n8)
        }
    }

    private var imapFields: some View {
        VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
            sectionLabel(Localized.Integrations.Imap.incomingSection)
            AppTextInput(label: Localized.Integrations.Imap.hostField, text: $imapHost)
            AppTextInput(label: Localized.Integrations.Imap.portField, text: $imapPort)
            AppTextInput(label: Localized.Integrations.Imap.usernameField, text: $imapUsername)
        }
    }

    private var smtpFields: some View {
        VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
            sectionLabel(Localized.Integrations.Imap.outgoingSection)
            AppTextInput(label: Localized.Integrations.Imap.hostField, text: $smtpHost)
            AppTextInput(label: Localized.Integrations.Imap.portField, text: $smtpPort)
            AppTextInput(label: Localized.Integrations.Imap.usernameField, text: $smtpUsername)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .typography(Typography.miniLabel)
            .foregroundStyle(colors.text.standard.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.n8)
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func connect() {
        let settings = IMAPAccountSettings(
            emailAddress: trimmed(emailAddress),
            imapHost: trimmed(imapHost),
            imapPort: Int(trimmed(imapPort)) ?? IMAPAccountSettings.defaultIMAPPort,
            smtpHost: trimmed(smtpHost),
            smtpPort: Int(trimmed(smtpPort)) ?? IMAPAccountSettings.defaultSMTPPort,
            imapUsername: trimmed(imapUsername).isEmpty ? nil : trimmed(imapUsername),
            smtpUsername: trimmed(smtpUsername).isEmpty ? nil : trimmed(smtpUsername),
            password: password
        )

        phase = .verifying
        Task {
            do {
                try await IMAPConnectionVerifier.verify(settings)
                if let existing {
                    // Reconnect: same id, same keychain namespace — only the
                    // labels and the stored credentials refresh.
                    existing.accountLabel = settings.emailAddress
                    existing.updatedAt = .now
                    credentialStore.save(settings, for: existing.id)
                    healthMonitor.clearNeedsReconnect(existing.id)
                } else {
                    let integration = Integration(
                        typeID: BundledIntegrationType.imap.id,
                        accountLabel: settings.emailAddress,
                        grantedCapabilities: [Capability.email.rawValue]
                    )
                    credentialStore.save(settings, for: integration.id)
                    modelContext.insert(integration)
                }
                Haptics.success()
                onConnected()
                dismiss()
            } catch {
                phase = .error(error.localizedDescription)
                Haptics.error()
            }
        }
    }

    private enum Phase: Equatable {
        case editing
        case verifying
        case error(String)
    }
}
