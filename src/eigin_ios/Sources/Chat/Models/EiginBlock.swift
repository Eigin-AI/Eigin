import Foundation

/// A supported, declarative component in an `eigin` Markdown fence.
enum EiginBlock: Equatable {
    case attribution(source: AttributionSource)

    /// Decodes the v1 allowlist; unsupported payloads remain ordinary code.
    static func parse(_ text: String) -> EiginBlock? {
        guard let data = text.data(using: .utf8),
              let fields = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              Set(fields.keys) == ["type", "source"],
              fields["type"] == "attribution",
              let rawSource = fields["source"],
              let source = AttributionSource(rawValue: rawSource)
        else { return nil }
        return .attribution(source: source)
    }
}

/// App-supported data providers with native attribution.
enum AttributionSource: String, Codable, Sendable {
    case appleWeather = "apple-weather"
}
