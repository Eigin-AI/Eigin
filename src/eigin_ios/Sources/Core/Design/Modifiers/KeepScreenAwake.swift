import SwiftUI
import UIKit

extension View {
    /// Keeps the screen awake while `active` is true. Restores the system idle
    /// timer on disappear or when `active` flips back to false.
    func keepScreenAwake(_ active: Bool) -> some View {
        modifier(KeepScreenAwakeModifier(active: active))
    }
}

private struct KeepScreenAwakeModifier: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .onAppear { UIApplication.shared.isIdleTimerDisabled = active }
            .onChange(of: active) { _, newValue in
                UIApplication.shared.isIdleTimerDisabled = newValue
            }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}
