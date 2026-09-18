import Foundation

extension URL {
    /// Scheme+host+path only — for logs, where a query could carry a token
    /// someone pasted into an address field.
    var diagnosticsAddress: String {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        return components?.url?.absoluteString ?? absoluteString
    }
}
