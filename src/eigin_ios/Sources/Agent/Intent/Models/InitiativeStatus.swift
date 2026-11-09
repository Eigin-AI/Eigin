import Foundation

/// The effective agreement state and next expected delivery shown on intent details.
struct InitiativeStatus {
    enum State {
        /// Switched off, or its intent or schedule is no longer active.
        case disabled
        /// Saved and enabled; notification registration is not confirmed yet.
        case pending
        /// Reconciliation confirmed notification registration.
        case scheduled
        /// Scheduling reported an error, available in `issue`.
        case failed

        var label: String {
            switch self {
            case .disabled: Localized.Intent.State.disabled
            case .pending: Localized.Intent.State.pending
            case .scheduled: Localized.Intent.State.scheduled
            case .failed: Localized.Intent.State.failed
            }
        }
    }

    let state: State
    let nextOccurrence: Date?
    let issue: String?
    let canCancel: Bool

    init(initiative: IntentInitiative, intent: Intent, now: Date = .now) {
        let schedule = intent.schedules.first { $0.id == initiative.scheduleID }
        canCancel = initiative.enabled
        issue = initiative.schedulingError
        if !initiative.enabled || intent.intentStatus != .active || schedule == nil {
            state = .disabled
        } else if initiative.schedulingError != nil {
            state = .failed
        } else if initiative.registrationStatus == "scheduled" {
            state = .scheduled
        } else {
            state = .pending
        }
        nextOccurrence = state != .disabled ? schedule?.nextOccurrence(onOrAfter: now) : nil
    }
}
