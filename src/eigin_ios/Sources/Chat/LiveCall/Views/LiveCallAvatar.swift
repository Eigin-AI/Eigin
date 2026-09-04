import SwiftUI

/// The agent's presence on the live call screen: the morphing blob as a
/// backdrop circle with the emoji popping into its centre a beat after the
/// blob lands.
///
/// Calm phases render a still, full-size circle; `intensity` carries how much
/// of the wobble is showing, owned by the caller so the phase story (thinking
/// vs speaking vs listening) stays on the call screen.
struct LiveCallAvatar: View {
    let emoji: String?
    var intensity: MorphIntensity

    @Environment(\.colors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var shownAt = Date.now
    @State private var facePopped = false

    /// The blob's slot — the whole composition scales off it.
    private static let size = 140.0

    /// The emoji is priced against the smallest blob so it always sits fully
    /// inside it, even mid-wobble.
    private static let minBlobDiameter = MorphBlob.minDiameter(in: size)
    static let emojiSize = minBlobDiameter * 0.72

    /// The big circle shouldn't dance as briskly as the chat-sized blob.
    /// Tuned by eye.
    private static let tempo = 0.6

    /// The full-screen cover is still animating in when the view appears;
    /// hold the blob's scale-in until the transition has settled.
    private static let entryDelay = 0.35

    var body: some View {
        ZStack {
            MorphBlob(
                shownAt: shownAt,
                intensity: intensity,
                tempo: Self.tempo,
                entryDelay: Self.entryDelay,
                color: colors.surface.standard.elevated
            )
            .frame(width: Self.size, height: Self.size)

            if let emoji {
                Text(emoji)
                    .font(.system(size: Self.emojiSize))
                    .id(emoji)
                    .scaleEffect(facePopped ? 1 : 0.2)
                    .opacity(facePopped ? 1 : 0)
                    .animation(
                        reduceMotion ? nil : .spring(duration: 0.6, bounce: 0.2),
                        value: facePopped
                    )
            }
        }
        .onAppear {
            // Anchor the choreography to the first visible frame — the view
            // is built while the full-screen cover is still animating in, so
            // initializing at build time would skip the entry scale.
            shownAt = .now
            if reduceMotion {
                facePopped = true
                return
            }
            // The blob lands first; the face arrives when it has settled.
            Task {
                try? await Task.sleep(for: .seconds(Self.entryDelay + MorphTimeline.entryDuration))
                facePopped = true
            }
        }
    }
}
