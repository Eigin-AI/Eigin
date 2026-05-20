import UIKit

/// Thin UIKit AppDelegate hosted by `EiginApp` via `@UIApplicationDelegateAdaptor`.
///
/// Exists only to surface lifecycle hooks SwiftUI doesn't yet expose — currently
/// the background `URLSession` relaunch path used by `GemmaModelDownloader`.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Eagerly instantiate the downloader so its `URLSession` is created with
        // the well-known identifier *before* iOS replays any background events.
        // Without this, the system can deliver `handleEventsForBackgroundURLSession`
        // for a session no instance is yet listening on.
        _ = GemmaModelDownloader.shared
        return true
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == AppKeys.downloadSessionIdentifier else {
            completionHandler()
            return
        }
        GemmaModelDownloader.shared.backgroundCompletionHandler = completionHandler
    }
}
