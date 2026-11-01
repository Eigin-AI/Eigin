import EiginSDKBindings

/// Apple host entry point for the portable SDK.
public enum EiginSDK {
    /// Initializes the SDK without changing application lifecycle or services.
    public static func initialize() async throws {
        try await EiginSDKBindings.initialize()
    }
}
