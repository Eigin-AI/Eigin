@testable import Eigin
import Testing

@Suite("OpenAICompatibleClientError.isModelNotFound")
struct OpenAICompatibleClientErrorModelNotFoundTests {
    @Test(arguments: [
        // OpenAI: 404 with structured code
        #"{"error":{"message":"The model `gpt-x` does not exist","code":"model_not_found"}}"#,
        // OpenAI prose, 400
        "The model 'gpt-old' does not exist or you do not have access to it.",
        "Unknown model: foo-bar",
        "invalid model id",
        "No such model",
        "That model is not available on this plan.",
    ])
    func detectsModelNotFound(body: String) {
        #expect(OpenAICompatibleClientError.httpError(404, body: body).isModelNotFound)
        #expect(OpenAICompatibleClientError.httpError(400, body: body).isModelNotFound)
    }

    @Test(arguments: [
        // Generic failures that must NOT be treated as model-not-found
        ("Not Found", 404),
        ("Resource not found", 404),
        (#"{"error":{"message":"Your credit balance is too low"}}"#, 400),
        ("Bad request: missing field", 400),
        ("", 404),
    ])
    func ignoresUnrelatedErrors(body: String, code: Int) {
        #expect(!OpenAICompatibleClientError.httpError(code, body: body).isModelNotFound)
    }

    @Test func ignoresNonModelStatusCodes() {
        let body = "model_not_found"
        #expect(!OpenAICompatibleClientError.httpError(401, body: body).isModelNotFound)
        #expect(!OpenAICompatibleClientError.httpError(500, body: body).isModelNotFound)
    }

    @Test func ignoresMissingBody() {
        #expect(!OpenAICompatibleClientError.httpError(404, body: nil).isModelNotFound)
        #expect(!OpenAICompatibleClientError.invalidResponse.isModelNotFound)
    }
}
