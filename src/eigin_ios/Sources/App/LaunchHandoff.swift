import SwiftUI

/// Picks up from the launch screen on returning launches: the launch mark on
/// the launch background, fading away over the app so it never hard-cuts in.
struct LaunchHandoff: View {
    let onFinished: () -> Void

    @State private var leaving = false

    var body: some View {
        ZStack {
            LaunchMark.background
            LaunchMark.image
                .resizable()
                .frame(width: LaunchMark.diameter, height: LaunchMark.diameter)
                .scaleEffect(leaving ? 0.92 : 1)
        }
        .ignoresSafeArea()
        .opacity(leaving ? 0 : 1)
        .allowsHitTesting(!leaving)
        .task {
            withAnimation(.easeOut(duration: Animations.slow)) { leaving = true }
            try? await Task.sleep(for: .seconds(Animations.slow))
            onFinished()
        }
    }
}
