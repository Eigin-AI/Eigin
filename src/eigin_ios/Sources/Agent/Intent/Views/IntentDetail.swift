import Factory
import SwiftUI

struct IntentDetail: View {
    @Environment(\.colors) private var colors
    @Injected(\.intentService) private var intentService
    @Environment(\.dismiss) private var dismiss

    let intent: Intent

    @State private var showDismissConfirmation = false

    var body: some View {
        List {
            Section {
                Text(intent.content)
                    .typography(Typography.body)
                    .foregroundStyle(colors.textPrimary)
            }

            Section(Localized.Ui.details) {
                LabeledContent(Localized.Ui.strength) {
                    HStack(spacing: Spacing.sm) {
                        strengthIndicator(intent.effectiveStrength)
                        Text(String(format: "%.0f%%", intent.effectiveStrength * 100))
                            .typography(Typography.callout)
                    }
                }
                LabeledContent(Localized.Ui.reinforced) {
                    Text(Localized.Ui.timesCountStr(String(intent.reinforcedCount)))
                        .typography(Typography.callout)
                }
                LabeledContent(Localized.Ui.created) {
                    Text(intent.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .typography(Typography.callout)
                        .foregroundStyle(colors.textSecondary)
                }
                LabeledContent(Localized.Tools.Last.updated) {
                    Text(intent.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        .typography(Typography.callout)
                        .foregroundStyle(colors.textSecondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(colors.background.ignoresSafeArea())
        .navigationTitle(Localized.Ui.intent, style: Typography.largeTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button(Localized.Ui.dismiss, role: .destructive) {
                    showDismissConfirmation = true
                }
            }
        }
        .alert(Localized.Ui.dismissIntent, isPresented: $showDismissConfirmation) {
            Button(Localized.Common.Actions.cancel, role: .cancel) {}
            Button(Localized.Ui.dismiss, role: .destructive) {
                Task {
                    try? await intentService.dismiss(id: intent.id)
                    dismiss()
                }
            }
        } message: {
            Text(Localized.Intent.dismissWarning)
        }
    }

    private func strengthIndicator(_ strength: Double) -> some View {
        Circle()
            .fill(strengthColor(strength))
            .frame(width: 8, height: 8)
    }

    private func strengthColor(_ strength: Double) -> Color {
        if strength > 0.7 { return .green }
        if strength > 0.3 { return .yellow }
        return .orange
    }
}
