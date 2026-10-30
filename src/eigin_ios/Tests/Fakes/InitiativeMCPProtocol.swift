import Foundation
import os

/// A credential-protected MCP endpoint for initiative-loop tests.
final class InitiativeMCPProtocol: URLProtocol, @unchecked Sendable {
    private static let calls = OSAllocatedUnfairLock(initialState: [String]())

    static var calledTools: [String] {
        calls.withLock { $0 }
    }

    static func reset() {
        calls.withLock { $0.removeAll() }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func stopLoading() {}

    override func startLoading() {
        guard request.value(forHTTPHeaderField: "Authorization") == "Bearer stored-token" else {
            respond(status: 401, payload: [:])
            return
        }
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = body["method"] as? String
        else {
            respond(status: 400, payload: [:])
            return
        }
        guard let id = body["id"] else {
            respond(status: 202, payload: [:])
            return
        }
        let params = body["params"] as? [String: Any] ?? [:]
        let result: [String: Any]
        switch method {
        case "initialize":
            result = [
                "protocolVersion": params["protocolVersion"] ?? "2025-11-25",
                "capabilities": ["tools": [:]],
                "serverInfo": ["name": "GitLab", "version": "1"],
                "instructions": "Use current GitLab data.",
            ]
        case "tools/list":
            result = ["tools": ["list_issues", "read_file", "delete_issue", "new_tool"].map {
                ["name": $0, "description": $0, "inputSchema": ["type": "object"]] as [String: Any]
            }]
        case "tools/call":
            let name = params["name"] as? String ?? ""
            Self.calls.withLock { $0.append(name) }
            result = ["content": [["type": "text", "text": "Current issue #324"]], "isError": false]
        default:
            respond(status: 400, payload: [:])
            return
        }
        respond(status: 200, payload: ["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func respond(status: Int, payload: [String: Any]) {
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url, statusCode: status, httpVersion: nil,
                  headerFields: ["Content-Type": "application/json"]
              ) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if status != 202, let data = try? JSONSerialization.data(withJSONObject: payload) {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }
}
