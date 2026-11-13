import Foundation
import SwiftData

extension InitiativeService {
    /// Reports saved agreements alongside the system's currently installed requests.
    func report(agentID: UUID, spaceID: UUID?) async throws -> [[String: Any]] {
        let saved = try list(agentID: agentID, spaceID: spaceID)
        let pending = await Set(scheduler.notifications.pending().map(\.identifier))
        let context = ModelContext(modelContainer)
        let registrations = try context.fetch(FetchDescriptor<InitiativeRegistration>())
        return saved.map { agreement in
            var result = WeekdayArguments.initiativeEntry(agreement)
            let installed = registrations.count(where: { registration in
                guard pending.contains(registration.id),
                      let delivery = try? JSONDecoder().decode(
                          InitiativeDelivery.self,
                          from: registration.payload
                      ) else { return false }
                return delivery.members.contains { $0.initiativeID.uuidString == agreement["id"] }
            })
            result["saved"] = true
            result["enabled"] = agreement["status"] != "disabled"
            result["registered_request_count"] = installed
            result["delivery_status"] = installed == 0 ? "not_registered" : agreement["status"] ==
                "scheduled" ? "scheduled" : "partial"
            return result
        }
    }
}

/// Tracks whether an operation crossed its persistence boundary before failing.
struct InitiativeOperationFailure: LocalizedError {
    enum ChangesState: String {
        case notSaved = "not_saved"
        case saved
        case unknown
    }

    let underlying: Error
    let changesState: ChangesState
    var errorDescription: String? {
        underlying.localizedDescription
    }
}

/// Stable tool response codes, independent of localized recovery instructions.
enum InitiativeFailureCode {
    static func code(for error: Error) -> String {
        if let failure = error as? InitiativeOperationFailure {
            return code(for: failure.underlying)
        }
        if error is IntentArgumentError { return "invalid_arguments" }
        if let error = error as? InitiativeScheduleError {
            switch error {
            case .unsupportedMonthlySchedule: return "unsupported_recurrence"
            case .capacityExceeded, .invalidRequestBudget: return "schedule_too_complex"
            default: return "invalid_schedule"
            }
        }
        if let error = error as? InitiativeError {
            switch error {
            case .permissionRequired: return "permission_required"
            case .busy: return "busy"
            case .inaccessibleIntent: return "inaccessible_intent"
            case .missingSchedule: return "missing_schedule"
            case .invalidContent, .invalidChanges: return "invalid_arguments"
            case .invalidIntentID: return "invalid_intent_id"
            case .invalidScheduleID: return "invalid_schedule_id"
            case .invalidInitiativeID: return "invalid_initiative_id"
            case .registrationFailed: return "registration_failed"
            default: return "unavailable"
            }
        }
        return "storage_error"
    }
}
