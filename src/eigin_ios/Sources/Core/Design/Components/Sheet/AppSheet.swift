import SwiftUI

/// A design-system sheet wrapper with consistent header and scrollable content areas.
///
/// The content is split into a **primary** area and an optional **secondary** area.
/// When secondary content is provided, it is separated from the primary by `Spacing.n40`.
struct AppSheet<Header: View, Primary: View, Secondary: View>: View {
    @ViewBuilder let header: () -> Header
    @ViewBuilder let primary: () -> Primary
    @ViewBuilder let secondary: () -> Secondary

    init(
        header: @escaping () -> Header,
        @ViewBuilder primary: @escaping () -> Primary,
        @ViewBuilder secondary: @escaping () -> Secondary = { EmptyView() }
    ) {
        self.header = header
        self.primary = primary
        self.secondary = secondary
    }

    private var hasSecondary: Bool {
        Secondary.self != EmptyView.self
    }

    var body: some View {
        VStack(spacing: Sizing.PageLayout.pyTop) {
            header()
            ScrollView {
                VStack(spacing: Sizing.PageLayout.gap) {
                    primary()
                    if hasSecondary {
                        secondary()
                    }
                }
                .padding(.bottom, Sizing.PageLayout.pyBottom)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.top, Sizing.PageLayout.pyTop)
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

// MARK: - Modifiers

extension View {
    func appSheet(
        isPresented: Binding<Bool>,
        title: String,
        label: String? = nil,
        description: String? = nil,
        detents: Set<PresentationDetent> = [.medium, .large],
        showsDismissButton: Bool = true,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder primary: @escaping () -> some View,
        @ViewBuilder secondary: @escaping () -> some View = { EmptyView() }
    ) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) {
            AppSheet {
                AppSheetHeader(
                    label: label,
                    title: title,
                    description: description,
                    onDismiss: showsDismissButton ? { isPresented.wrappedValue = false } : nil
                )
            } primary: {
                primary()
            } secondary: {
                secondary()
            }
            .presentationDetents(detents)
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(Radius.card)
            .presentationBackground { SheetBackground() }
        }
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
