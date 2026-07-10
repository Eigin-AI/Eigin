import Foundation

/// Fetches the connected Microsoft account's address for display, using the
/// access token issued at connect time. Feeds ``IntegrationType/accountLabel``.
enum MicrosoftAccountInfo {
    static func email(accessToken: String) async -> String? {
        var request = URLRequest(
            url: URL(string: "https://graph.microsoft.com/v1.0/me?$select=mail,userPrincipalName")!
        )
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode)
        else { return nil }
        // Personal accounts sometimes leave `mail` unset; `userPrincipalName`
        // (the sign-in identifier, e.g. the outlook.com address) always is.
        struct MeResponse: Decodable {
            let mail: String?
            let userPrincipalName: String?
        }
        guard let me = try? JSONDecoder().decode(MeResponse.self, from: data) else { return nil }
        return me.mail ?? me.userPrincipalName
    }
}
