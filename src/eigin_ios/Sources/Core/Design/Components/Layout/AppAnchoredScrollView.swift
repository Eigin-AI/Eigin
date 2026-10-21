import SwiftUI

/// A scroll view for bottom-anchored screens: the design's flex-column
/// pages whose trailing action sits at the bottom when content is short and
/// scrolls below it when content is long — the web equivalent of the trailing
/// `Spacer` picking up `margin-top: auto`. Content is given the visible height
/// as a minimum, so the spacer only absorbs genuinely leftover space.
struct AppAnchoredScrollView<Content: View, Header: View>: View {
    @ViewBuilder let content: () -> Content
    @ViewBuilder let header: () -> Header

    var body: some View {
        SoftEdgeScrollView(fillsViewport: true, content: content, header: header)
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
    } header: {
        AppNavigationHeader(title: "Title", leading: { EmptyView() })
    }
    .previewEnvironment()
}
