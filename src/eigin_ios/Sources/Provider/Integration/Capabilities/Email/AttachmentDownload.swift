import Foundation

/// Reads a provider response with an enforced byte ceiling and absolute download deadline.
enum AttachmentDownload {
    static func get(
        _ url: URL, token: String, session: URLSession,
        deadline: Date, limit: Int = EmailAttachmentLimits.transportBytes
    ) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await read(
                    url,
                    token: token,
                    session: session,
                    deadline: deadline,
                    limit: limit
                )
            }
            group.addTask {
                let remaining = deadline.timeIntervalSinceNow
                guard remaining > 0 else { throw URLError(.timedOut) }
                try await Task.sleep(for: .seconds(remaining))
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    private static func read(
        _ url: URL,
        token: String,
        session: URLSession,
        deadline: Date,
        limit: Int
    ) async throws -> Data {
        try Task.checkCancellation()
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else { throw URLError(.timedOut) }
        var request = URLRequest(url: url)
        request.timeoutInterval = remaining
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (bytes, response) = try await session.bytes(
            for: request,
            delegate: NoAttachmentRedirects()
        )
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200 ... 299).contains(http.statusCode) else {
            if http.statusCode == 404 { throw EmailProviderError.notFound }
            throw EmailProviderError
                .requestFailed("Attachment request returned HTTP \(http.statusCode).")
        }
        guard response.expectedContentLength <= limit else {
            throw EmailProviderError
                .requestFailed("Attachment response exceeds the download limit.")
        }
        var data = Data()
        for try await byte in bytes {
            if data.count % 16384 == 0 {
                try Task.checkCancellation()
                guard deadline > Date() else { throw URLError(.timedOut) }
            }
            guard data.count < limit else {
                throw EmailProviderError
                    .requestFailed("Attachment response exceeds the download limit.")
            }
            data.append(byte)
        }
        try Task.checkCancellation()
        guard deadline > Date() else { throw URLError(.timedOut) }
        return data
    }

    /// Appends opaque provider identifiers as single URL path segments.
    static func url(_ base: URL, segments: [String]) -> URL {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_~"))
        for segment in segments {
            components.percentEncodedPath += "/" + segment
                .addingPercentEncoding(withAllowedCharacters: allowed)!
        }
        return components.url!
    }
}

/// Provider attachment endpoints must not redirect an authenticated request elsewhere.
private final class NoAttachmentRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}
