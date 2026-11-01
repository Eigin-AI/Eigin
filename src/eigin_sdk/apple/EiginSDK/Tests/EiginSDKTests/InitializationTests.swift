import EiginSDK
import Testing

@Test func initializesThroughRustRepeatedly() async throws {
    try await EiginSDK.initialize()
    try await EiginSDK.initialize()
}
