import EiginSDK
import Foundation
import Testing

@Test(arguments: [URLError.notConnectedToInternet, .timedOut, .secureConnectionFailed, .networkConnectionLost])
func preservesURLSessionErrorCategories(code: URLError.Code) async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FailingURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let client = EiginSDK.Experimental.Inference.OpenAICompatible(configuration: .init(
        baseUrl: "https://network-error.test/\(code.rawValue)", apiToken: "fake", extraHeaders: [:]
    ), session: session)
    do {
        _ = try await client.fetchModels()
        Issue.record("Expected network error")
    } catch let error as URLError {
        #expect(error.code == code)
    }
}

private final class FailingURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let code = request.url?.pathComponents.dropFirst().first.flatMap(Int.init) ?? -1
        client?.urlProtocol(self, didFailWithError: URLError(URLError.Code(rawValue: code)))
    }

    override func stopLoading() {}
}
