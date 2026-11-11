import EiginSDKBindings
import Foundation

/// Apple host entry point for the portable SDK.
public enum EiginSDK {
    /// Bundled license and copyright notices for SDK runtime dependencies.
    public static var thirdPartyNoticesURL: URL {
        Bundle.module.url(forResource: "THIRD-PARTY-NOTICES", withExtension: "txt")!
    }

    /// SDK metadata and dependency notices with shared license texts.
    public static var licenseCatalogURL: URL {
        Bundle.module.url(forResource: "NOTICES", withExtension: "json")!
    }

    /// Initializes the SDK without changing application lifecycle or services.
    public static func initialize() async throws {
        try await EiginSDKBindings.initialize()
    }
}
