import SwiftUI

/// A scroll view for bottom-anchored screens: the design's flex-column
/// pages whose trailing action sits at the bottom when content is short and
/// scrolls below it when content is long — the web equivalent of the trailing
/// `Spacer` picking up `margin-top: auto`. Content is given the viewport as a
/// minimum height, so the spacer only absorbs genuinely leftover space.
struct AppAnchoredScrollView<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                content()
                    .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

#Preview {
    AppAnchoredScrollView {
        VStack(spacing: Spacing.n16) {
            Text("Short content")
            Spacer(minLength: 0)
            AppButton("Bottom") {}
        }
        .padding(.horizontal, Spacing.n16)
    }
    .previewEnvironment()
}
