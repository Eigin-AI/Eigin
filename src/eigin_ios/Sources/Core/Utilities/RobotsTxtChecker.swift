import Foundation

/// Checks whether a URL is accessible to bots according to the site's `robots.txt`.
///
/// Conservative: if the fetch fails or parsing is ambiguous, returns `false`
/// (fall back to visible browsing).
enum RobotsTxtChecker {
    /// Returns `true` if `robots.txt` allows our user-agent to access the given URL's path.
    static func isAllowed(url: URL) async -> Bool {
        guard let scheme = url.scheme, let host = url.host,
              let robotsURL = URL(string: "\(scheme)://\(host)/robots.txt")
        else { return false }

        var request = URLRequest(url: robotsURL)
        request.timeoutInterval = 5

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse
        else { return false }

        // If robots.txt doesn't exist (404), assume everything is allowed.
        if httpResponse.statusCode == 404 { return true }
        guard (200 ..< 300).contains(httpResponse.statusCode) else { return false }

        guard let body = String(data: data, encoding: .utf8) else { return false }

        let path = url.path.isEmpty ? "/" : url.path
        return parse(body, path: path)
    }

    // MARK: - Parsing

    /// Parses `robots.txt` content and checks `User-agent: *` rules against `path`.
    private static func parse(_ content: String, path: String) -> Bool {
        var inWildcardBlock = false
        var disallowedPaths: [String] = []
        var allowedPaths: [String] = []

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            // Strip comments
            let effective: String = if let hashIndex = line.firstIndex(of: "#") {
                String(line[..<hashIndex]).trimmingCharacters(in: .whitespaces)
            } else {
                line
            }
            guard !effective.isEmpty else { continue }

            let parts = effective.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            if key == "user-agent" {
                inWildcardBlock = value == "*"
            } else if inWildcardBlock {
                if key == "disallow", !value.isEmpty {
                    disallowedPaths.append(value)
                } else if key == "allow", !value.isEmpty {
                    allowedPaths.append(value)
                }
            }
        }

        // Most-specific rule wins (longest matching prefix).
        let bestAllow = allowedPaths.filter { path.hasPrefix($0) }.max(by: { $0.count < $1.count })
        let bestDisallow = disallowedPaths.filter { path.hasPrefix($0) }
            .max(by: { $0.count < $1.count })

        if let allow = bestAllow, let disallow = bestDisallow {
            return allow.count >= disallow.count
        }
        if bestDisallow != nil { return false }
        return true
    }
}
