import Factory
import SwiftUI

/// Shared entry point to the agent's retained waiting invitations.
struct WaitingInitiativeAvatar: View {
    let agentID: UUID?
    let emoji: String?
    @Injected(\.initiativeService) private var service
    @Environment(\.colors) private var colors
    @State private var isPresented = false
    @State private var launchID: UUID?
    @State private var error: String?

    private var invitations: [WaitingMessage] {
        service.invitations(for: agentID)
    }

    var body: some View {
        Button { isPresented = true } label: {
            AppBrandAvatar(emoji: emoji)
                .overlay(alignment: .topTrailing) {
                    WaitingInitiativeBadge(count: invitations.count)
                        .offset(x: Spacing.n8, y: -Spacing.n2)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Localized.Intent.Waiting.avatarLabel(invitations.count.formatted()))
        .accessibilityIdentifier("waiting-initiatives-avatar")
        .appSheet(
            isPresented: $isPresented,
            title: Localized.Intent.Waiting.title,
            description: invitations.isEmpty ? nil : Localized.Intent.Waiting.description,
            onDismiss: {
                if let launchID {
                    PendingDestination.set(.chat(launchID))
                    self.launchID = nil
                }
            }
        ) {
            VStack(spacing: Spacing.n12) {
                if invitations.isEmpty {
                    AppEmptyState(
                        icon: Iconography.Functional.sparkles,
                        title: Localized.Intent.Waiting.emptyTitle,
                        description: Localized.Intent.Waiting.emptyDescription
                    )
                } else {
                    ForEach(invitations) { invitation in
                        card(invitation)
                    }
                }
            }
            .padding(.horizontal, Sizing.PageLayout.ContentGrouping.Px.mobile)
            .alert(Localized.Intent.initiativeFailed, isPresented: Binding(
                get: { error != nil }, set: { if !$0 { error = nil } }
            )) {
                Button(Localized.Common.Actions.ok, role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }

    private func card(_ invitation: WaitingMessage) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                do {
                    launchID = try service.openInvitation(id: invitation.id)
                    isPresented = false
                } catch { self.error = error.localizedDescription }
            } label: {
                VStack(alignment: .leading, spacing: Spacing.n12) {
                    Text(timestamp(invitation.dueAt))
                        .typography(Typography.tag)
                        .foregroundStyle(colors.text.standard.muted)
                    Text(invitation.body)
                        .typography(Typography.titleXS)
                        .foregroundStyle(colors.text.standard.base)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.vertical, Spacing.n24)
                .padding(.leading, Spacing.n20)
                .padding(.trailing, Spacing.n40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                do { try service.dismissInvitation(id: invitation.id) }
                catch { self.error = error.localizedDescription }
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(colors.icon.standard.muted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Localized.Intent.Waiting.dismissLabel(invitation.body))
            .padding(Spacing.n4)
        }
        .background(
            colors.surface.standard.elevated,
            in: RoundedRectangle(cornerRadius: Radius.card)
        )
    }

    private func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: AppLanguage.current.speechLocaleIdentifier)
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: date)
    }
}

/// Starts settled in each header and animates subsequent count changes only.
private struct WaitingInitiativeBadge: View {
    let count: Int
    @Environment(\.colors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedCount: Int
    @State private var isVisible: Bool
    @State private var isOnScreen = false

    init(count: Int) {
        self.count = count
        _displayedCount = State(initialValue: max(1, count))
        _isVisible = State(initialValue: count > 0)
    }

    var body: some View {
        Text(displayedCount, format: .number)
            .typography(Typography.miniLabel)
            .contentTransition(.numericText(value: Double(displayedCount)))
            .foregroundStyle(colors.surface.standard.base)
            .frame(minWidth: Spacing.n20, minHeight: Spacing.n20)
            .background(colors.text.standard.base, in: Circle())
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : 0.8)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
            .onAppear {
                settle()
                isOnScreen = true
            }
            .onDisappear { isOnScreen = false }
            .onChange(of: count) { _, next in
                guard isOnScreen, !reduceMotion else {
                    settle()
                    return
                }
                if next > 0, !isVisible {
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { displayedCount = next }
                }
                withAnimation(.easeInOut(duration: Animations.fast)) {
                    if next > 0 { displayedCount = next }
                    isVisible = next > 0
                }
            }
    }

    private func settle() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if count > 0 { displayedCount = count }
            isVisible = count > 0
        }
    }
}
