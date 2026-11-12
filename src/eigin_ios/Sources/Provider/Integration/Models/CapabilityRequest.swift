import Foundation

/// A chat asking the person to connect what a skill needs.
struct CapabilityRequest: Identifiable, Equatable {
    let id = UUID()
    /// What the skill needs; all of it must end up connected.
    let capabilities: Set<Capability>
    /// Ids of the integrations that could provide the capabilities, in
    /// catalogue order.
    let providerIDs: [String]
    /// Who is asking, for the sheet's description.
    let agentName: String

    /// A preset uses the same chat presentation without inventing capabilities.
    var presetID: String?

    var providers: [IntegrationType] {
        providerIDs.compactMap(BundledIntegrationType.type(forID:))
    }
}

/// How a request to connect a capability ended.
enum CapabilityConnectResult: Sendable {
    case connected
    /// An explicit choice to leave the service unconnected.
    case declined
    /// Setup or the reply was stopped without a decision.
    case cancelled
    /// Setup failed before a connection could be verified.
    case failed(String)

    /// Dismissing an error reports it without recording a refusal.
    static func dismissed(failure: String?) -> Self {
        if let failure { .failed(failure) } else { .cancelled }
    }
}

/// Asks the person to connect a capability and waits for the answer. Only a
/// chat on screen can ask; without one, connecting is declined straight away.
typealias ConnectCapabilityHandler = @Sendable @MainActor (CapabilityRequest) async
    -> CapabilityConnectResult
