import SwiftUI

/// A design-system sheet wrapper with consistent header and scrollable content areas.
///
/// The content is split into a **primary** area and an optional **secondary** area.
/// When secondary content is provided, it is separated from the primary by `Spacing.n40`.
struct AppSheet<Header: View, Primary: View, Secondary: View>: View {
    @ViewBuilder let header: () -> Header
    @ViewBuilder let primary: () -> Primary
    @ViewBuilder let secondary: () -> Secondary
    /// When set, reports the sheet's intrinsic height (header + content) so the presenter can size
    /// a
    /// detent to fit. Independent of the available height, so it never feeds back through the
    /// detent.
    var intrinsicHeight: Binding<CGFloat>?

    init(
        header: @escaping () -> Header,
        @ViewBuilder primary: @escaping () -> Primary,
        @ViewBuilder secondary: @escaping () -> Secondary = { EmptyView() },
        intrinsicHeight: Binding<CGFloat>? = nil
    ) {
        self.header = header
        self.primary = primary
        self.secondary = secondary
        self.intrinsicHeight = intrinsicHeight
    }

    @State private var headerHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    /// The safe areas a fitted detent has to span. Measured on a background
    /// that ignores the safe area, since in-flow views only ever see what's
    /// left after it.
    @State private var sheetInsets = EdgeInsets()

    private var hasSecondary: Bool {
        Secondary.self != EmptyView.self
    }

    var body: some View {
        // The header floats over the scroll, so content softens into it.
        SoftEdgeScrollView(softens: .top) {
            VStack(spacing: Sizing.PageLayout.gap) {
                primary()
                if hasSecondary {
                    secondary()
                }
            }
            .padding(.bottom, Sizing.PageLayout.pyBottom)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                contentHeight = $0
                reportIntrinsicHeight()
            }
            .padding(.top, Sizing.PageLayout.pyTop)
        } header: {
            header()
                // Keep the header at its ideal height: once the presentation
                // clamps to a fitted detent, a squeezed frame never changes
                // and a late rewrap (Dynamic Type, another locale) could
                // never grow the detent back.
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    headerHeight = $0
                    reportIntrinsicHeight()
                }
                .padding(.top, Sizing.PageLayout.pyTop)
        }
        .environment(\.softEdgeShape, .sheet)
        .frame(maxWidth: .infinity, alignment: .top)
        .background {
            GeometryReader { _ in
                Color.clear
                    .ignoresSafeArea(edges: [.top, .bottom])
                    .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: {
                        if sheetInsets != $0 {
                            sheetInsets = $0
                            reportIntrinsicHeight()
                        }
                    }
            }
        }
    }

    private func reportIntrinsicHeight() {
        guard let intrinsicHeight else { return }
        // Top padding + header + the gap below it + content,
        // plus the safe areas the presentation leaves outside the scroll view: a
        // detent's height spans them too, so a fitted sheet that leaves them out
        // undershoots and clips its last row into the bottom edge.
        let total = sheetInsets.top + sheetInsets.bottom
            + Sizing.PageLayout.pyTop + headerHeight + Sizing.PageLayout.pyTop + contentHeight
        if abs(intrinsicHeight.wrappedValue - total) > 0.5 {
            intrinsicHeight.wrappedValue = total
        }
    }
}

// MARK: - Modifiers

extension View {
    func appSheet(
        isPresented: Binding<Bool>,
        title: String,
        label: String? = nil,
        description: String? = nil,
        descriptionContent: AnyView? = nil,
        detents: Set<PresentationDetent> = [.medium, .large],
        fitsContent: Bool = false,
        showsDismissButton: Bool = true,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder primary: @escaping () -> some View,
        @ViewBuilder secondary: @escaping () -> some View = { EmptyView() }
    ) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) {
            AppSheetContainer(
                label: label,
                title: title,
                description: description,
                descriptionContent: descriptionContent,
                detents: detents,
                fitsContent: fitsContent,
                onDismiss: showsDismissButton ? { isPresented.wrappedValue = false } : nil,
                primary: primary,
                secondary: secondary
            )
        }
    }
}

/// Presents an ``AppSheet`` and resolves its detents. With `fitsContent`, it sizes a single detent
/// to
/// the measured content height so the sheet hugs its content and only scrolls when it would
/// overflow.
private struct AppSheetContainer<Primary: View, Secondary: View>: View {
    let label: String?
    let title: String
    let description: String?
    let descriptionContent: AnyView?
    let detents: Set<PresentationDetent>
    let fitsContent: Bool
    let onDismiss: (() -> Void)?
    @ViewBuilder let primary: () -> Primary
    @ViewBuilder let secondary: () -> Secondary

    @State private var fittedHeight: CGFloat = 0

    private var resolvedDetents: Set<PresentationDetent> {
        if fitsContent, fittedHeight > 0 {
            return [.height(fittedHeight)]
        }
        return detents
    }

    var body: some View {
        AppSheet(
            header: {
                AppSheetHeader(
                    label: label,
                    title: title,
                    description: description,
                    descriptionContent: descriptionContent,
                    onDismiss: onDismiss
                )
            },
            primary: primary,
            secondary: secondary,
            intrinsicHeight: fitsContent ? $fittedHeight : nil
        )
        .presentationDetents(resolvedDetents)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Radius.card)
        .presentationBackground { SheetBackground() }
    }
}

/// A content-fitted sheet whose view draws its own header — for stepful flows
/// whose title and description change as the sheet advances, which the
/// `title`-based `.appSheet` API cannot express. Reuses ``AppSheet``'s
/// measurement so the presentation hugs the content at any font size.
struct AppFittedSheet<Header: View, Primary: View, Secondary: View>: View {
    @ViewBuilder let header: () -> Header
    @ViewBuilder let primary: () -> Primary
    @ViewBuilder let secondary: () -> Secondary
    /// Fixed detents in place of content-fitting. iOS 26 floats partial-height
    /// sheets and snaps full-height ones flush, so a sheet whose height crosses
    /// that boundary changes width; a flow that swaps between tall and short
    /// states can avoid the jump by presenting at one fixed detent.
    var detents: Set<PresentationDetent>?

    init(
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder primary: @escaping () -> Primary,
        @ViewBuilder secondary: @escaping () -> Secondary = { EmptyView() },
        detents: Set<PresentationDetent>? = nil
    ) {
        self.header = header
        self.primary = primary
        self.secondary = secondary
        self.detents = detents
    }

    @State private var fittedHeight: CGFloat = 0
    @Environment(\.colors) private var colors

    private var resolvedDetents: Set<PresentationDetent> {
        if let detents { return detents }
        return fittedHeight > 0 ? [.height(fittedHeight)] : [.large]
    }

    var body: some View {
        AppSheet(
            header: header,
            primary: primary,
            secondary: secondary,
            intrinsicHeight: detents == nil ? $fittedHeight : nil
        )
        .presentationDetents(resolvedDetents)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Radius.card)
        .presentationBackground { SheetBackground() }
    }
}

private struct SheetBackground: View {
    @Environment(\.colors) private var colors
    var body: some View {
        colors.surface.standard.base
    }
}

// MARK: - Preview

#Preview {
    AppSheetGallery()
        .resolveTheme()
}

private struct AppSheetGallery: View {
    @State private var showEpisode = false
    @State private var showWizard = false
    @State private var showConfirm = false
    @State private var showLong = false
    @Environment(\.colors) private var colors

    var body: some View {
        ZStack {
            colors.surface.standard.base.ignoresSafeArea()
            VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                AppSubtleActionButton("Episode info", icon: Image(systemName: "pencil")) {
                    showEpisode = true
                }
                AppSubtleActionButton("Step wizard", icon: Image(systemName: "list.number")) {
                    showWizard = true
                }
                AppSubtleActionButton(
                    "Confirmation",
                    icon: Image(systemName: "exclamationmark.triangle")
                ) {
                    showConfirm = true
                }
                AppSubtleActionButton("Long content", icon: Image(systemName: "text.alignleft")) {
                    showLong = true
                }
            }
            .padding(.horizontal, Spacing.n24)
        }
        .appSheet(isPresented: $showEpisode, title: "Edit episode", detents: [.medium]) {
            EpisodeSheetContent()
        }
        .appSheet(isPresented: $showWizard, title: "How did you sleep?", detents: [.medium]) {
            WizardSheetContent()
        }
        .appSheet(isPresented: $showConfirm, title: "Delete recording", showsDismissButton: false) {
            ConfirmSheetContent(onCancel: { showConfirm = false })
        } secondary: {
            AppSubtleActionButton("Permanently delete", icon: Image(systemName: "trash")) {}
                .padding(.horizontal, contentPx)
        }
        .appSheet(isPresented: $showLong, title: "Preferences", detents: [.medium, .large]) {
            LongSheetContent()
        }
    }
}

private let contentPx = Sizing.PageLayout.ContentGrouping.Px.mobile
private let contentGap = Sizing.PageLayout.ContentGrouping.gap

private struct EpisodeSheetContent: View {
    @Environment(\.colors) private var colors

    var body: some View {
        VStack(spacing: contentGap) {
            VStack(alignment: .leading, spacing: Spacing.n16) {
                row(label: "Title", value: "Morning run")
                row(label: "Date", value: "15 May 2026")
                row(label: "Duration", value: "32 min")
            }
            .padding(.horizontal, Sizing.Input.Px.left)
            .padding(.vertical, Spacing.n24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.surface.standard.alternative)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
            .padding(.horizontal, contentPx)

            AppSubtleActionButton("Add a note", icon: Image(systemName: "plus")) {}
                .padding(.horizontal, contentPx)

            AppButton("Save changes", variant: .secondary) {}
                .padding(.horizontal, contentPx)
        }
    }

    private func row(label: String, value: String) -> some View {
        HStack(spacing: Spacing.n16) {
            Text(label)
                .typography(Typography.description)
                .foregroundStyle(colors.text.standard.base)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .typography(Typography.description)
                .foregroundStyle(colors.text.standard.muted)
        }
    }
}

private struct WizardSheetContent: View {
    @State private var selected: Int? = nil

    var body: some View {
        VStack(spacing: contentGap) {
            AppSelectorButton("Great", isSelected: selected == 0) { selected = 0 }
                .padding(.horizontal, contentPx)
            AppSelectorButton("Good", isSelected: selected == 1) { selected = 1 }
                .padding(.horizontal, contentPx)
            AppSelectorButton("OK", isSelected: selected == 2) { selected = 2 }
                .padding(.horizontal, contentPx)
            AppSelectorButton("Poor", isSelected: selected == 3) { selected = 3 }
                .padding(.horizontal, contentPx)
            AppButton("Continue") {}
                .padding(.horizontal, contentPx)
                .disabled(selected == nil)
        }
    }
}

private struct ConfirmSheetContent: View {
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: contentGap) {
            AppButton("Delete", variant: .destructive) {}
                .padding(.horizontal, contentPx)
            AppButton("Cancel", variant: .secondary) { onCancel() }
                .padding(.horizontal, contentPx)
        }
    }
}

private struct LongSheetContent: View {
    var body: some View {
        VStack(spacing: contentGap) {
            ForEach(
                [
                    "Notifications",
                    "Privacy",
                    "Appearance",
                    "Language",
                    "Storage",
                    "Integrations",
                    "Advanced",
                    "About",
                ],
                id: \.self
            ) { item in
                AppSubtleActionButton(item, icon: Image(systemName: "chevron.right")) {}
                    .padding(.horizontal, contentPx)
            }
        }
    }
}
