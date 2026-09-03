import SwiftUI

/// Third-party AI disclosure footnote at the bottom of the hosted-inference
/// sheets, with a tappable "See the privacy policy" link. A quiet footnote:
/// present before the user commits, without competing with the sheet's content.
struct ThirdPartyDisclosureText: View {
    /// Where the conversation goes when the user proceeds.
    enum Variant {
        /// Through Eigin's relay, which forwards to providers on Eigin's behalf.
        case eiginCloud
        /// Straight from the device to a provider the user connects, under its terms.
        case ownProvider
    }

    let variant: Variant

    @Environment(\.colors) private var colors

    var body: some View {
        Text(sentence)
            .typography(Typography.note)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Spacing.n8)
    }

    private var sentence: AttributedString {
        // A shade quieter than body text: footnote tone, before the user commits.
        var text = AttributedString(bodyText)
        text.foregroundColor = colors.text.standard.disabled

        // Own line below the body keeps the disclosure readable.
        var link = AttributedString("\n" + Localized.Provider.Disclosure.privacyLink)
        link.foregroundColor = colors.text.standard.link
        // Config-driven URL, shared with Settings → About. The fallback always
        // populates it; an absent link simply renders inert.
        if let url = AppKeys.privacyPolicyURL {
            link.link = url
        }

        text += link
        return text
    }

    private var bodyText: String {
        switch variant {
        case .eiginCloud: Localized.Provider.Disclosure.eiginCloud
        case .ownProvider: Localized.Provider.Disclosure.ownProvider
        }
    }
}

#Preview {
    VStack(spacing: Spacing.n24) {
        ThirdPartyDisclosureText(variant: .eiginCloud)
        ThirdPartyDisclosureText(variant: .ownProvider)
    }
    .padding(Spacing.n24)
    .previewEnvironment()
}
