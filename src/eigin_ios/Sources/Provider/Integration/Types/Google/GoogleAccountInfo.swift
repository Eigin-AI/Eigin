import Foundation

/// Fetches the connected Google account's email address for display, using
/// the access token issued at connect time. Feeds ``IntegrationType/accountLabel``.
enum GoogleAccountInfo {
    static func email(accessToken: String) async -> String? {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode)
        else { return nil }
        struct UserInfo: Decodable { let email: String? }
        return try? JSONDecoder().decode(UserInfo.self, from: data).email
    }
}
