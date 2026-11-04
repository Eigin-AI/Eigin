import Foundation

extension KnownModelCatalog {
    static let mistralLargeReasoning = ReasoningControl(
        supportedEfforts: [.low, .medium, .high], fastEffort: .low, escalatedEffort: .high
    )
    static let mistralMediumReasoning = ReasoningControl(
        supportedEfforts: [.none, .high], fastEffort: .none, escalatedEffort: .high
    )

    /// Controls are enabled only for verified model/endpoint contracts.
    static func reasoningControl(for model: String, baseURL: String) -> ReasoningControl? {
        guard let entry = lookup(model), let control = entry.reasoningControl else { return nil }
        if ProviderPreset.isRelay(baseURL) {
            // These IDs and aliases map to official Mistral upstreams in models.toml.
            let models = [
                "mistral/mistral-large-4-0", "mistral-large-4-0", "mistral-large-4",
                "mistral/mistral-medium-2604", "mistral-medium-3-5",
                "mistralai/Mistral-Medium-3.5-128B", "Mistral-Medium-3.5-128B",
            ]
            return models.contains(model) ? control : nil
        }
        guard let url = URL(string: baseURL), url.scheme == "https",
              url.host == "api.mistral.ai",
              ["mistral-large-4", "mistral-large-4-0", "mistral-medium-3-5"].contains(model)
        else { return nil }
        return control
    }
}
