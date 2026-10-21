import SwiftUI

/// A vertical scroll whose content softens at each edge, with a header and
/// footer floating over it. The standard scroll for a screen or sheet.
///
/// Wraps ``View/softEdge(header:footer:)`` around one ScrollView of its own,
/// which suits screens of modest length. A long or lazy feed, like the chat
/// feed, applies ``View/softEdge(header:footerHeight:)`` to its own scroll so
/// it can keep owning its geometry (viewport metrics, bottom anchoring).
struct SoftEdgeScrollView<Content: View, Header: View, Footer: View>: View {
    private let fillsViewport: Bool
    private let floatingFooterHeight: CGFloat?
    private let softens: VerticalEdge.Set
    private let content: Content
    private let header: Header
    private let footer: Footer

    @State private var viewportHeight: CGFloat = 0

    /// - Parameters:
    ///   - fillsViewport: Stretches the content to at least the visible
    ///     height, so a trailing `Spacer` pins an action to the bottom when the
    ///     content is short.
    ///   - floatingFooterHeight: The height of a footer floated by someone
    ///     else, such as the tab bar, which also reserves its own room.
    ///   - softens: The edges that soften. Sheets soften only the top.
    init(
        fillsViewport: Bool = false,
        floatingFooterHeight: CGFloat? = nil,
        softens: VerticalEdge.Set = .all,
        @ViewBuilder content: () -> Content,
        @ViewBuilder header: () -> Header,
        @ViewBuilder footer: () -> Footer
    ) {
        self.fillsViewport = fillsViewport
        self.floatingFooterHeight = floatingFooterHeight
        self.softens = softens
        self.content = content()
        self.header = header()
        self.footer = footer()
    }

    var body: some View {
        ScrollView {
            content
                .frame(
                    maxWidth: .infinity,
                    minHeight: fillsViewport ? viewportHeight : nil,
                    alignment: .top
                )
        }
        .scrollBounceBehavior(.basedOnSize)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.containerSize.height - geometry.contentInsets.top - geometry.contentInsets
                .bottom
        } action: { _, newValue in
            viewportHeight = max(0, newValue)
        }
        .modifier(SoftEdgeScroll(
            header: header,
            footer: footer,
            floatingFooterHeight: floatingFooterHeight,
            softens: softens
        ))
    }
}

extension SoftEdgeScrollView where Footer == EmptyView {
    init(
        fillsViewport: Bool = false,
        floatingFooterHeight: CGFloat? = nil,
        softens: VerticalEdge.Set = .all,
        @ViewBuilder content: () -> Content,
        @ViewBuilder header: () -> Header
    ) {
        self.init(
            fillsViewport: fillsViewport,
            floatingFooterHeight: floatingFooterHeight,
            softens: softens,
            content: content,
            header: header,
            footer: { EmptyView() }
        )
    }
}

extension SoftEdgeScrollView where Header == EmptyView, Footer == EmptyView {
    init(
        fillsViewport: Bool = false,
        softens: VerticalEdge.Set = .all,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            fillsViewport: fillsViewport,
            softens: softens,
            content: content,
            header: { EmptyView() },
            footer: { EmptyView() }
        )
    }
}

extension SoftEdgeScrollView where Footer == EmptyView {
    /// A root tab screen: the tab bar floats over the bottom, outside the screen.
    static func tabRoot(
        @ViewBuilder content: () -> Content,
        @ViewBuilder header: () -> Header
    ) -> SoftEdgeScrollView {
        SoftEdgeScrollView(
            floatingFooterHeight: AppNavigationBar.height,
            content: content,
            header: header
        )
    }
}
