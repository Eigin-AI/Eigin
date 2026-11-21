import EiginSDK

extension KnownModelCatalog {
    static func boundedReasoningEffort(
        _ effort: ReasoningEffort?, model: String, baseURL: String
    ) -> ReasoningEffort? {
        EiginSDK.ModelCatalog.boundedReasoningEffort(effort?.sdk, model: model, baseURL: baseURL)
            .map(ReasoningEffort.init)
    }

    static func reasoningControl(for model: String, baseURL: String) -> ReasoningControl? {
        EiginSDK.ModelCatalog.reasoningControl(model: model, baseURL: baseURL)
            .map(ReasoningControl.init)
    }
}
