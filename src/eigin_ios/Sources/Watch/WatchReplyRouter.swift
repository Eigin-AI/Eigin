/// Decides who announces a watch answer on the wrist — the phone or the
/// watch — so we don't accidentally deliver the same notification twice.
///
/// - `.live` (`sendMessage`): the watch app has the answer right now and
///   posts the notification.
/// - `.queued` (`transferUserInfo`): the phone posts the notification iOS
///   mirrors to the wrist; the watch stays quiet when the answer lands.
///
/// Compiled into both targets rather than shared through a module.
enum WatchReplyRouter {
    /// How the phone delivered the answer.
    enum Transport {
        /// `sendMessage`: in the watch app's hands right now.
        case live
        /// `transferUserInfo`: arrives whenever the watch app next runs.
        case queued
    }

    /// Which end of the pair posts the notification for a transport.
    enum Announcer {
        case phone
        case watch
    }

    /// The announcement for a delivery is owned by the side whose channel
    /// carried it.
    static func announcer(for transport: Transport) -> Announcer {
        switch transport {
        case .live: .watch
        case .queued: .phone
        }
    }
}
