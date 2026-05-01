import Foundation

struct ProviderSnapshot {
    let name: String
    let baseURL: String

    var isLocal: Bool {
        ProviderPreset.isLocal(baseURL)
    }
}
