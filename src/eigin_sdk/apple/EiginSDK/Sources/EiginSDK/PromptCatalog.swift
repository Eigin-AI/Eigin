import EiginSDKBindings

public extension EiginSDK {
    /// Immutable embedded or host-supplied prompts. Loading requires no SDK initialization.
    typealias PromptCatalog = EiginSDKBindings.PromptCatalog

    /// Catalog validation, usage preflight, and rendering failures.
    typealias PromptCatalogError = EiginSDKBindings.PromptCatalogError
}
