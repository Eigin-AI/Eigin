import Factory
import SwiftUI

struct IntentDetail: View {
    @Injected(\.intentService) private var intentService
    @Environment(\.dismiss) private var dismiss

    let intent: Intent

    @State private var showDismissConfirmation = false

    @State private var isDismissing = false
    @State private var showDismissError = false

    var body: some View {
        AppSecondaryScreen(title: Localized.Ui.intent) {
            AppContentGroup(label: Localized.Intent.content) {
                AppDetailText(text: intent.content)
            }
            if !intent.tasks.isEmpty {
                AppRowsGroup(label: Localized.Intent.tasks, rows: intent.tasks.map { task in
                    AppRowSpec(
                        id: "\(task.id)",
                        title: task.content,
                        description: task.due.map { LocalDateFormatter.string(from: $0) },
                        icon: task.completed ? Iconography.Functional.check : nil,
                        accessory: .none,
                        tone: task.completed ? .muted : .standard
                    )
                })
            }
            if !intent.events.isEmpty {
                AppRowsGroup(label: Localized.Intent.events, rows: intent.events.map { event in
                    AppRowSpec(
                        id: "\(event.id)",
                        title: event.content,
                        description: LocalDateFormatter.string(from: event.at),
                        accessory: .none
                    )
                })
            }
            if !intent.schedules.isEmpty {
                AppRowsGroup(
                    label: Localized.Intent.schedules,
                    rows: intent.schedules.map { schedule in
                        AppRowSpec(
                            id: "\(schedule.id)",
                            title: schedule.content,
                            description: scheduleSummary(schedule),
                            accessory: .none
                        )
                    }
                )
            }
            AppRowsGroup(label: Localized.Ui.details, rows: [
                AppRowSpec(
                    title: Localized.Ui.created,
                    value: intent.createdAt.formatted(date: .abbreviated, time: .shortened),
                    accessory: .none
                ),
                AppRowSpec(
                    title: Localized.Intent.updated,
                    value: intent.updatedAt.formatted(date: .abbreviated, time: .shortened),
                    accessory: .none
                ),
            ])
            AppRowsGroup(rows: [AppRowSpec(
                title: Localized.Intent.dismissAction,
                accessory: .trash,
                tone: .destructive,
                action: { showDismissConfirmation = true }
            )])
            .disabled(isDismissing)
        }
        .alert(Localized.Ui.dismissIntent, isPresented: $showDismissConfirmation) {
            Button(Localized.Common.Actions.cancel, role: .cancel) {}
            Button(Localized.Ui.dismiss, role: .destructive) {
                guard !isDismissing else { return }
                isDismissing = true
                Task {
                    defer { isDismissing = false }
                    do {
                        try await intentService.dismiss(id: intent.id)
                        dismiss()
                    } catch { showDismissError = true }
                }
            }
        } message: {
            Text(Localized.Intent.dismissWarning)
        }
        .alert(Localized.Intent.dismissFailed, isPresented: $showDismissError) {
            Button(Localized.Common.Actions.ok, role: .cancel) {}
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
