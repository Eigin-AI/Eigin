import SwiftUI

/// A circular avatar carrying the agent's presence.
///
/// With an `emoji` the circle softens to a neutral surface and shows the
/// agent's symbol — the same vessel as the onboarding avatar. Without one it
/// falls back to the brand mark on the brand spot color. The emoji pops in
/// the first time it appears; the symbol is memoized, so recurring loads
/// render instantly and a changed identity pops again.
struct AppBrandAvatar: View {
    /// The agent's symbol; nil falls back to the brand mark.
    let emoji: String?
    let fallback: Image
    let size: CGFloat
    let insets: EdgeInsets
    let action: (() -> Void)?

    @Environment(\.colors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(Self.shownEmojiKey) private var shownEmoji: String = ""
    @State private var facePopped = false

    /// The emoji state is shared app-wide so the pop happens once, not once
    /// per header per launch.
    private static let shownEmojiKey = "agentAvatarShownEmoji"

    init(
        emoji: String? = nil,
        fallback: Image = Iconography.Brand.avatar,
        size: CGFloat = 56,
        insets: EdgeInsets = EdgeInsets(
            top: Spacing.n8,
            leading: Spacing.n8,
            bottom: Spacing.n8,
            trailing: Spacing.n8
        ),
        action: (() -> Void)? = nil
    ) {
        self.emoji = emoji
        self.fallback = fallback
        self.size = size
        self.insets = insets
        self.action = action
    }

    private var face: String? {
        guard let emoji, !emoji.isEmpty else { return nil }
        return emoji
    }

    var body: some View {
        avatar(background: face == nil ? colors.surface.impact.base : colors.surface
            .standard.elevated)
    }

    /// Settled from `facePopped` or the memoized symbol.
    private var isFaceSettled: Bool {
        facePopped || face == shownEmoji
    }

    @ViewBuilder
    private var faceOrFallback: some View {
        if let face {
            Text(face)
                .font(.system(size: size * 0.55))
                .id(face)
                .scaleEffect(isFaceSettled ? 1 : 0.2)
                .opacity(isFaceSettled ? 1 : 0)
        } else {
            fallback
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(colors.text.standard.base)
                .padding(insets)
        }
    }

    private func avatar(background: Color) -> some View {
        faceOrFallback
            .frame(width: size, height: size)
            .background(background)
            .clipShape(Circle())
            .onAppear(perform: settleFace)
            .onChange(of: emoji, initial: false) { _, _ in settleFace() }
    }

    /// Reveal memoized symbols instantly; pop only a symbol seen for the
    /// first time (fresh install, or a changed identity).
    private func settleFace() {
        guard let face else { return }
        if face == shownEmoji {
            facePopped = true
            return
        }
        shownEmoji = face
        facePopped = false
        if reduceMotion {
            facePopped = true
            return
        }
        withAnimation(.spring(duration: 0.6, bounce: 0.2)) { facePopped = true }
    }
}

// MARK: - Preview

#Preview("Light") {
    BrandAvatarPreview()
        .resolveTheme()
}

#Preview("Dark") {
    BrandAvatarPreview()
        .resolveTheme()
        .environment(\.colorScheme, .dark)
}

#Preview("Pressable") {
    BrandAvatarPreview(action: {})
        .resolveTheme()
}

private struct BrandAvatarPreview: View {
    @Environment(\.colors) private var colors
    let action: (() -> Void)?

    init(action: (() -> Void)? = nil) {
        self.action = action
    }

    var body: some View {
        ZStack {
            colors.surface.standard.base.ignoresSafeArea()
            VStack(spacing: Spacing.n16) {
                // The agent's face on its neutral vessel.
                AppBrandAvatar(
                    emoji: "🫥",
                    fallback: Image(systemName: "apple.logo"),
                    action: action
                )
                // Brand-mark fallback.
                AppBrandAvatar(fallback: Image(systemName: "apple.logo"), action: action)
            }
        }
    }
}
