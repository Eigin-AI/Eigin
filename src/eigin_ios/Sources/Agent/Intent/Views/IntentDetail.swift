import Factory
import SwiftUI

struct IntentDetail: View {
    @Environment(\.colors) private var colors
    @Injected(\.intentService) private var intentService
    @Environment(\.dismiss) private var dismiss

    let intent: Intent

    @State private var showDismissConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            AppNavigationHeader(
                title: Localized.Ui.intent,
                leading: {
                    AppActionButton(
                        icon: Iconography.Functional.Arrow.left,
                        variant: .open,
                        size: .medium,
                        action: { dismiss() }
                    )
                },
                trailing: {
                    AppActionButton(
                        icon: Image(systemName: "xmark"),
                        variant: .open,
                        size: .medium,
                        action: { showDismissConfirmation = true }
                    )
                }
            )

            List {
                Section {
                    Text(intent.content)
                        .typography(Typography.body)
                        .foregroundStyle(colors.text.standard.base)
                }

                if !intent.tasks.isEmpty {
                    Section(Localized.Intent.tasks) {
                        ForEach(intent.tasks) { task in
                            taskRow(task)
                        }
                    }
                }

                if !intent.events.isEmpty {
                    Section(Localized.Intent.events) {
                        ForEach(intent.events) { event in
                            LabeledContent(event.content) {
                                Text(LocalDateFormatter.string(from: event.at))
                                    .typography(Typography.note)
                                    .foregroundStyle(colors.text.standard.muted)
                            }
                        }
                    }
                }

                if !intent.schedules.isEmpty {
                    Section(Localized.Intent.schedules) {
                        ForEach(intent.schedules) { schedule in
                            LabeledContent(schedule.content) {
                                Text(scheduleSummary(schedule))
                                    .typography(Typography.note)
                                    .foregroundStyle(colors.text.standard.muted)
                            }
                        }
                    }
                }

                Section(Localized.Ui.details) {
                    LabeledContent(Localized.Ui.created) {
                        Text(intent.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .typography(Typography.note)
                            .foregroundStyle(colors.text.standard.muted)
                    }
                    LabeledContent(Localized.Tools.Last.updated) {
                        Text(intent.updatedAt.formatted(date: .abbreviated, time: .shortened))
                            .typography(Typography.note)
                            .foregroundStyle(colors.text.standard.muted)
                    }
                }
            }
            .contentMargins(.top, 0, for: .scrollContent)
            .scrollContentBackground(.hidden)
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
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

    private func taskRow(_ task: IntentTask) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.n8) {
            Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(task.completed ? colors.text.standard.muted : colors.text.standard
                    .base)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.content)
                    .typography(Typography.body)
                    .foregroundStyle(colors.text.standard.base)
                    .strikethrough(task.completed)
                if let due = task.due {
                    Text(LocalDateFormatter.string(from: due))
                        .typography(Typography.miniLabel)
                        .foregroundStyle(colors.text.standard.muted)
                }
            }
        }
    }

    /// A compact human-readable description of a recurring schedule.
    private func scheduleSummary(_ schedule: IntentSchedule) -> String {
        var parts: [String] = []
        switch schedule.frequency {
        case .daily:
            parts.append("Daily")
        case .weekly:
            let symbols = Calendar.current.shortWeekdaySymbols
            let days = (schedule.weekdays ?? [])
                .compactMap { (1 ... 7).contains($0) ? symbols[$0 - 1] : nil }
            parts.append(days.isEmpty ? "Weekly" : "Weekly on \(days.joined(separator: ", "))")
        case .monthly:
            let days = (schedule.monthDays ?? []).map(String.init)
            parts.append(days.isEmpty ? "Monthly" : "Monthly on \(days.joined(separator: ", "))")
        }
        if let hour = schedule.hour {
            parts.append(String(format: "at %02d:%02d", hour, schedule.minute ?? 0))
        }
        return parts.joined(separator: " ")
    }
}
