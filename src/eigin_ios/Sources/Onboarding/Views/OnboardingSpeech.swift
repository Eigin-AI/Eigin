import SwiftUI

/// The avatar's spoken line, centered beneath it: a title that drops in and
/// fades (simulating the Markdown header the agent would use in chat), a short
/// beat, then the body streamed in through the same ``StreamThrottler`` the chat
/// uses, so it reads as the agent actually saying it.
///
/// Reports completion through `done`, which the scaffold uses to reveal the
/// screen's content only once the agent has finished speaking. Re-plays whenever
/// `title` or `text` changes.
struct OnboardingSpeech: View {
    let title: String
    let text: String
    /// Set to the spoken `text` once it has finished streaming. Lets the scaffold
    /// reveal content only for the line currently on screen, with no lag when the
    /// line changes.
    var finished: Binding<String> = .constant("")
    /// Beat before the title appears, letting the avatar land first.
    var titleDelay: Duration = .zero
    /// Beat between the title appearing and the body streaming.
    var streamDelay: Duration = OnboardingTiming.streamDelay

    @Environment(\.colors) private var colors
    @State private var throttler = StreamThrottler()
    @State private var titleShown = false

    var body: some View {
        // A header sits 16pt above body text, measured cap to baseline as on web.
        VStack(
            spacing: Spacing.n16 - Typography.titleM.lineBoxInset - Typography.standfirst
                .lineBoxInset
        ) {
            Text(verbatim: title)
                .typography(Typography.titleM)
                .foregroundStyle(colors.text.standard.base)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(titleShown ? 1 : 0)
                // Drops in from slightly above as it fades.
                .offset(y: titleShown ? 0 : -8)

            // The full line is laid out from the start, with the unrevealed part
            // transparent. Line breaks are therefore fixed, so words pop into
            // their final positions instead of reflowing as they appear.
            Text(attributedBody)
                .typography(Typography.standfirst)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .task(id: title + "\u{1}" + text) {
            await play()
        }
    }

    /// The body line with the revealed prefix coloured and the rest transparent.
    private var attributedBody: AttributedString {
        var attributed = AttributedString(text)
        attributed.foregroundColor = colors.text.standard.muted

        let characters = attributed.characters
        let revealed = min(throttler.displayedText.count, characters.count)
        let split = characters.index(characters.startIndex, offsetBy: revealed)
        attributed[split...].foregroundColor = .clear
        return attributed
    }

    private func play() async {
        titleShown = false
        throttler.reset()

        try? await Task.sleep(for: titleDelay)
        withAnimation(.easeOut(duration: 0.45)) { titleShown = true }
        try? await Task.sleep(for: streamDelay)

        guard !text.isEmpty else {
            finished.wrappedValue = text
            return
        }

        throttler.start()
        for chunk in Self.streamChunks(text) {
            throttler.feed(chunk)
            try? await Task.sleep(for: OnboardingTiming.wordInterval)
        }
        throttler.finish()

        // Wait for the throttler to finish draining the buffered words.
        while throttler.phase != .done, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(16))
        }
        // A beat after the line lands, then the screen's content eases in.
        try? await Task.sleep(for: OnboardingTiming.contentDelay)
        withAnimation(.easeOut(duration: Animations.normal)) {
            finished.wrappedValue = text
        }
    }

    /// Splits text into word-sized chunks (each carrying its leading space) to
    /// emulate a model stream feeding the throttler.
    private static func streamChunks(_ text: String) -> [String] {
        text.split(separator: " ", omittingEmptySubsequences: false)
            .enumerated()
            .map { index, word in index == 0 ? String(word) : " " + word }
    }
}

#Preview {
    OnboardingSpeech(
        title: "Let's make this yours.",
        text: "I'm Eigin, your personal AI. I live on your device, and I answer to you."
    )
    .padding(Spacing.n24)
    .resolveTheme()
}
