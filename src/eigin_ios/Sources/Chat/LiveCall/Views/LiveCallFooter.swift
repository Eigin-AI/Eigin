import SwiftUI

/// Footer for live call mode — live text stream + call controls inside a `ChatBottomBox`.
struct LiveCallFooter: View {
    let service: LiveCallService
    let onEnd: () -> Void

    var body: some View {
        ChatBottomBox {
            VStack(spacing: Spacing.n16) {
                LiveCallStatus(service: service)
                LiveCallControls(service: service, onEnd: onEnd)
            }
        }
    }
}
