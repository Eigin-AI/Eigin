import Foundation

/// Retains a sheet's request until dismissal completes before presenting the next one.
@Observable @MainActor
final class PermissionPresentation {
    private(set) var active: PermissionRequest?
    private var pending: PermissionRequest?
    var isPresented = false

    func update(_ request: PermissionRequest?) {
        pending = request
        if let active {
            if active.id != request?.id { isPresented = false }
        } else {
            active = request
            isPresented = request != nil
        }
    }

    /// Returns the dismissed request so a swipe can resolve only that request.
    func didDismiss() -> PermissionRequest? {
        let dismissed = active
        active = nil
        if pending?.id == dismissed?.id { pending = nil }
        active = pending
        isPresented = active != nil
        return dismissed
    }
}
