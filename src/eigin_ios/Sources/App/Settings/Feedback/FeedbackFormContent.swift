import Factory
import SwiftUI

struct FeedbackFormContent: View {
    @Environment(\.colors) private var colors
    @AppStorage(StorageKey.logSinkToFile) private var logSinkToFile = false

    @State private var feedbackType: FeedbackType = .bug
    @State private var description = ""
    @State private var includeLogs = false
    @State private var report: FeedbackReport?
    @FocusState private var descriptionFocused: Bool

    var body: some View {
        VStack(spacing: Sizing.PageLayout.gap) {
            VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                typeSection
                descriptionField
                if logSinkToFile {
                    logsToggle
                }
            }

            AppButton(Localized.Settings.Feedback.continueButton) {
                descriptionFocused = false
                report = FeedbackReport(
                    type: feedbackType,
                    description: description,
                    includeLogs: includeLogs
                )
            }
            .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.horizontal, contentPx)
        }
        .sheet(item: $report) { report in
            FeedbackReportSheet(report: report)
        }
    }

    // MARK: - Subviews

    private var typeSection: some View {
        Picker("", selection: $feedbackType) {
            ForEach(FeedbackType.allCases) { type in
                Text(type.displayName).tag(type)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Sizing.Input.Px.left)
        .frame(height: Sizing.Input.height)
        .background(colors.surface.standard.alternative)
        .clipShape(Capsule())
        .padding(.horizontal, contentPx)
    }

    private var descriptionField: some View {
        ZStack(alignment: .topLeading) {
            if description.isEmpty {
                Text(Localized.Settings.Feedback.descriptionPlaceholder)
                    .typography(Typography.description)
                    .foregroundStyle(colors.text.standard.muted)
                    .padding(.horizontal, Sizing.Input.Px.left)
                    .padding(.vertical, Spacing.n16)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $description)
                .typography(Typography.description)
                .foregroundStyle(colors.text.standard.base)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, Sizing.Input.Px.left - 5)
                .padding(.vertical, Spacing.n8)
                .frame(minHeight: 250)
                .focused($descriptionFocused)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button {
                            descriptionFocused = false
                        } label: {
                            Image(systemName: "checkmark")
                        }
                    }
                }
        }
        .background(colors.surface.standard.alternative)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .padding(.horizontal, contentPx)
    }

    private var logsToggle: some View {
        Toggle(Localized.Settings.Feedback.includeLogs, isOn: $includeLogs)
            .typography(Typography.description)
            .foregroundStyle(colors.text.standard.base)
            .padding(.horizontal, contentPx + Spacing.n8)
    }
}

// MARK: - Report sheet wrapper

private struct FeedbackReportSheet: View {
    let report: FeedbackReport
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colors) private var colors

    var body: some View {
        AppSheet {
            AppSheetHeader(
                title: Localized.Settings.Feedback.reportTitle,
                description: Localized.Settings.Feedback.reportDescription(AppKeys.supportEmail),
                onDismiss: { dismiss() }
            )
        } primary: {
            FeedbackReportContent(report: report)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Radius.card)
        .presentationBackground { colors.surface.standard.base }
    }
}

private let contentPx = Sizing.PageLayout.ContentGrouping.Px.mobile
private let contentGap = Sizing.PageLayout.ContentGrouping.gap

// MARK: - Preview

#Preview {
    Color.clear
        .appSheet(isPresented: .constant(true), title: "Send Feedback", detents: [.large]) {
            FeedbackFormContent()
        }
        .previewEnvironment()
}
