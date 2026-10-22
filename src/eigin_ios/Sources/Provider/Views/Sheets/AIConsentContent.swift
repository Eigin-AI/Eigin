import SwiftUI

/// What is shared with a cloud AI and where it goes, then the question.
///
/// Shared by both ways into cloud AI: the last step of connecting your own
/// provider, and a sheet of its own for the Eigin Relay. Rows are ordered by
/// how often each thing is sent: always, when relevant, only if allowed.
struct AIConsentContent: View {
    /// Who receives the conversation.
    enum Recipient: Equatable {
        case relay
        /// A provider the user connects, with its privacy policy when known.
        case provider(name: String, privacyPolicyURL: String?)

        /// The sheet title that asks the question.
        var title: String {
            switch self {
            case .relay: Localized.Provider.Consent.relayTitle
            case .provider(let name, _): Localized.Provider.Consent.title(name)
            }
        }

        /// The sheet description that says why it is asked.
        var description: String {
            switch self {
            case .relay: Localized.Provider.Consent.relayDescription
            case .provider: Localized.Provider.Consent.description
            }
        }
    }

    let recipient: Recipient
    let onAllow: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(spacing: Sizing.PageLayout.gap) {
            AppRowsGroup(
                label: Localized.Provider.Consent.groupLabel,
                rows: [
                    point(
                        icon: Iconography.Functional.note,
                        title: Localized.Provider.Consent.conversationTitle,
                        body: Localized.Provider.Consent.conversationBody
                    ),
                    point(
                        icon: Iconography.Functional.sparkles,
                        title: Localized.Provider.Consent.memoriesTitle,
                        body: Localized.Provider.Consent.memoriesBody
                    ),
                    point(
                        icon: Iconography.Functional.search,
                        title: Localized.Provider.Consent.connectedTitle,
                        body: Localized.Provider.Consent.connectedBody
                    ),
                    AppRowSpec(
                        title: Localized.Provider.Consent.destinationTitle,
                        descriptionContent: destination,
                        icon: Iconography.Functional.globe,
                        accessory: .none
                    ),
                ]
            )

            VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                AppButton(Localized.Provider.Consent.allow) { onAllow() }
                AppButton(Localized.Common.Actions.notNow, variant: .secondary) { onDecline() }
            }
        }
    }

    private func point(icon: Image, title: String, body: String) -> AppRowSpec {
        AppRowSpec(title: title, description: body, icon: icon, accessory: .none)
    }

    /// Who gets it, with the policy that governs it linked inline.
    private var destination: AttributedString {
        let markdown: String = switch recipient {
        case .relay:
            Localized.Provider.Consent.destinationRelay(
                AppKeys.privacyPolicyURL?.absoluteString ?? ""
            )
        case .provider(let name, let url?):
            Localized.Provider.Consent.destinationOwn(name, url)
        case .provider(let name, nil):
            Localized.Provider.Consent.destinationOwnUnlinked(name)
        }
        return (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
    }
}

#Preview("Relay") {
    AIConsentContent(recipient: .relay, onAllow: {}, onDecline: {})
        .padding(Spacing.n16)
        .previewEnvironment()
}

#Preview("Own provider") {
    AIConsentContent(
        recipient: .provider(
            name: "OpenAI",
            privacyPolicyURL: "https://openai.com/policies/privacy-policy/"
        ),
        onAllow: {},
        onDecline: {}
    )
    .padding(Spacing.n16)
    .previewEnvironment()
}

extension AIConsentContent.Recipient {
    /// Who receives what is sent to `provider`.
    init(provider: Provider) {
        if ProviderPreset.isRelay(provider.baseURL) {
            self = .relay
        } else {
            let preset = ProviderPreset.all.first { $0.baseURL == provider.baseURL }
            self = .provider(name: provider.name, privacyPolicyURL: preset?.privacyPolicyURL)
        }
    }
}
