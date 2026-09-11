#if DEBUG || EIGIN_DEV
import Foundation

/// A fake ``ProviderModelRefresher`` that returns a scripted model list and records calls.
@MainActor
final class FakeProviderModelRefresher: ProviderModelRefresher {
    var modelsToReturn: [String]
    private(set) var refreshCallCount = 0

    init(modelsToReturn: [String] = []) {
        self.modelsToReturn = modelsToReturn
    }

    @discardableResult
    func refresh(_ provider: Provider, apiKeyOverride _: String?) async throws -> [String] {
        refreshCallCount += 1
        provider.availableModels = modelsToReturn
        provider.updatedAt = .now
        return modelsToReturn
    }
}
#endif
