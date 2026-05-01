import Foundation

struct LocalModelStatus: Identifiable {
    enum State {
        case ready
        case notDownloaded
        case downloading(progress: Double)
        case unavailable(reason: String)
    }

    let id: String
    let displayName: String
    let state: State
}
