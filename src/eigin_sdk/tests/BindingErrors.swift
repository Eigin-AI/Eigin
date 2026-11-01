import Foundation

@main
struct BindingErrors {
    static func main() async throws {
        try await initialize()
        do {
            try await failInitializationFixture()
            fatalError("Expected a typed Rust error")
        } catch let InitializationError.Unavailable(reason) {
            precondition(reason == "binding fixture")
        }
        print("Swift typed Rust error propagation passed")
    }
}
