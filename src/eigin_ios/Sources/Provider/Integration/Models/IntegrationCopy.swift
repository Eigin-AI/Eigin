import Foundation

/// Shared integration copy that needs data formatting, so screens don't each
/// hand-concatenate sentences.
enum IntegrationCopy {
    /// The partial-consent warning: connected, but scopes were skipped, and
    /// reconnecting is how you get them. `ListFormatter` joins the names the
    /// way the current locale punctuates a list ("a, b and c").
    static func partialGrant(accountLabel: String, ungranted: Set<Capability>) -> String {
        let names = ungranted.map(\.displayName).sorted()
        return Localized.Integration.partialGrant(
            accountLabel,
            ListFormatter.localizedString(byJoining: names)
        )
    }
}
