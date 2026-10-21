import SwiftUI

/// Soft edges on both ends of a scroll view, for a header and footer that
/// float over it with no surface of their own.
///
/// Empty safe-area insets reserve the header and footer heights, so the
/// content scrolls beneath them. The header, footer and soft edges are drawn
/// in one overlay, soft edges below the controls. Each soft edge shows only
/// while content is scrolled past its edge.
///
/// With no header or footer a soft edge is just its transition, anchored to the
/// scroll's edge, or the screen edge where the scroll reaches it. With one, it
/// spans the control and its safe area, plus the transition.
struct SoftEdgeScroll<Header: View, Footer: View>: ViewModifier {
    struct Edges: Equatable {
        var top = false
        var bottom = false
    }

    let header: Header
    let footer: Footer
    /// Set when the footer floats outside this modifier and reports its own height.
    let floatingFooterHeight: CGFloat?
    /// The edges that soften. Sheets soften only the top.
    var softens: VerticalEdge.Set = .all

    @State private var edges = Edges()
    @State private var headerHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0
    /// The safe area above the scroll: the status bar on a screen, none in a sheet.
    @State private var topInset: CGFloat = 0
    /// The home indicator's area, below a footer. See ``WindowSafeArea``.
    @State private var bottomInset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Edges.self) { geometry in
                // Offsets are relative to the insets the header and footer reserve.
                let visibleBottom = geometry.contentOffset.y + geometry.containerSize.height
                    - geometry.contentInsets.bottom
                return Edges(
                    top: geometry.contentOffset.y + geometry.contentInsets.top > 1,
                    bottom: visibleBottom < geometry.contentSize.height - 1
                )
            } action: { _, newValue in
                edges = newValue
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: headerHeight)
            }
            // A floating footer's caller reserves its own room.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: footerHeight)
            }
            .scrollEdgeEffectHidden()
            // Measured outside the insets above, which the scroll's own safe
            // area already includes.
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: {
                topInset = $0
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { _ in
                bottomInset = WindowSafeArea.bottom
            }
            .overlay {
                ZStack {
                    if softens.contains(.top) {
                        SoftEdge(
                            edge: .top,
                            inset: headerHeight > 0 ? topInset : 0,
                            controlHeight: headerHeight,
                            isActive: edges.top
                        )
                        .ignoresSafeArea(.container, edges: [.top, .horizontal])
                    }
                    if softens.contains(.bottom) {
                        SoftEdge(
                            edge: .bottom,
                            inset: bottomControl > 0 ? bottomInset : 0,
                            controlHeight: bottomControl,
                            isActive: edges.bottom
                        )
                        .ignoresSafeArea(.container, edges: [.bottom, .horizontal])
                    }
                    VStack(spacing: 0) {
                        header.onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                            headerHeight = $0
                        }
                        Spacer(minLength: 0)
                        footer.onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                            footerHeight = $0
                        }
                    }
                }
            }
    }

    /// The footer's height, floated here or by the caller.
    private var bottomControl: CGFloat {
        floatingFooterHeight ?? footerHeight
    }
}

/// Device-level safe area, read from the window so it never includes the
/// keyboard inset.
///
/// Read it only in callbacks such as `onAppear` or a geometry change's action,
/// never in a view body: the window asks SwiftUI about the status bar, and
/// doing that mid-layout re-enters the view graph and hangs the app.
enum WindowSafeArea {
    static var bottom: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first?
            .windows.first(where: { $0.isKeyWindow })?
            .safeAreaInsets.bottom ?? 0
    }
}

extension View {
    /// Softens the content at each edge of a scroll view, only while more
    /// content lies beyond it. The header and footer float over the scroll.
    /// Attach after any safe-area changes to the scroll view, so the soft
    /// edges can reach the screen edges.
    func softEdge(
        @ViewBuilder header: () -> some View,
        @ViewBuilder footer: () -> some View
    ) -> some View {
        modifier(SoftEdgeScroll(header: header(), footer: footer(), floatingFooterHeight: nil))
    }

    /// Like ``softEdge(header:footer:)``, for a footer the caller floats over
    /// the scroll itself, such as a composer overlay. `footerHeight` is its
    /// measured height; the caller reserves that room in the content.
    func softEdge(
        @ViewBuilder header: () -> some View,
        footerHeight: CGFloat
    ) -> some View {
        modifier(SoftEdgeScroll(
            header: header(),
            footer: EmptyView(),
            floatingFooterHeight: footerHeight
        ))
    }

    /// Softens the content at each edge of a scroll view with a header floating over it.
    func softEdge(@ViewBuilder header: () -> some View) -> some View {
        softEdge(header: header, footer: { EmptyView() })
    }

    /// Softens the content at each edge of a scroll view with nothing floating over it.
    func softEdge() -> some View {
        softEdge(header: { EmptyView() }, footer: { EmptyView() })
    }
}
