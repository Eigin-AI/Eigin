import Foundation

/// Remembers that the person said no to a capability, so a chat asks once.
///
/// A no is Not now on a connect sheet, or removing the integration that
/// provided it. Connecting clears it. Lives in `UserDefaults` rather than the
/// schema, like an asset's declined download.
struct DeclinedCapabilities: @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Every capability the person has said no to.
    var declined: Set<Capability> {
        Set(Capability.allCases.filter(isDeclined))
    }

    func isDeclined(_ capability: Capability) -> Bool {
        defaults.bool(forKey: StorageKey.capabilityDeclined(capability.rawValue))
    }

    func decline(_ capability: Capability) {
        defaults.set(true, forKey: StorageKey.capabilityDeclined(capability.rawValue))
    }

    func clear(_ capability: Capability) {
        defaults.removeObject(forKey: StorageKey.capabilityDeclined(capability.rawValue))
    }

    /// Whether setup for a bundled MCP preset was declined.
    func isPresetDeclined(_ presetID: String) -> Bool {
        defaults.bool(forKey: StorageKey.mcpPresetDeclined(presetID))
    }

    /// Suppresses repeated chat offers until the preset is connected from Settings.
    func declinePreset(_ presetID: String) {
        defaults.set(true, forKey: StorageKey.mcpPresetDeclined(presetID))
    }

    /// Clears a declined preset after successful setup.
    func clearPreset(_ presetID: String) {
        defaults.removeObject(forKey: StorageKey.mcpPresetDeclined(presetID))
    }
}
