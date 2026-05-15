import SwiftUI

struct PulseModifier: ViewModifier {
    let isActive: Bool
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isActive && isPulsing ? 0.7 : 1.0) // TODO: This should be a design token
            .animation(
                isActive
                    ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsing
            )
            .onChange(of: isActive) { _, active in isPulsing = active }
            .onAppear { if isActive { isPulsing = true } }
    }
}

extension View {
    func pulse(isActive: Bool) -> some View {
        modifier(PulseModifier(isActive: isActive))
    }
}
