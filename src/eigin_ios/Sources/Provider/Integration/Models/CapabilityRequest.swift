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

    var providers: [IntegrationType] {
        providerIDs.compactMap(BundledIntegrationType.type(forID:))
    }
}

/// How a request to connect a capability ended.
enum CapabilityConnectResult: Sendable {
    case connected
    /// Not now, or closing the sheet before connecting.
    case declined
    /// The reply was stopped while the sheet was up: not an answer either way.
    case cancelled
}

/// Asks the person to connect a capability and waits for the answer. Only a
/// chat on screen can ask; without one, connecting is declined straight away.
typealias ConnectCapabilityHandler = @Sendable @MainActor (CapabilityRequest) async
    -> CapabilityConnectResult
