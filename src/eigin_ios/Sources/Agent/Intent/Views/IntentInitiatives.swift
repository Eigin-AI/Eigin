import Factory
import SwiftData
import SwiftUI

/// Initiative status and controls for one intent.
/// Owns the live query separately from the detail screen's navigation state.
struct IntentInitiatives: View {
    let intent: Intent

    @Query private var initiatives: [IntentInitiative]
    @State private var initiativeError: String?

    init(intent: Intent) {
        self.intent = intent
        let intentID = intent.id
        _initiatives = Query(filter: #Predicate<IntentInitiative> { $0.intentID == intentID })
    }

    var body: some View {
        ForEach(initiatives) { initiative in
            AppRowsGroup(label: Localized.Intent.initiatives, rows: initiativeRows(initiative))
        }
        .alert(
            Localized.Intent.initiativeFailed,
            isPresented: Binding(
                get: { initiativeError != nil },
                set: { if !$0 { initiativeError = nil } }
            )
        ) {
            Button(Localized.Common.Actions.ok, role: .cancel) {}
        } message: { Text(initiativeError ?? "") }
    }

    private func initiativeRows(_ initiative: IntentInitiative) -> [AppRowSpec] {
        let status = InitiativeStatus(initiative: initiative, intent: intent)
        var rows = [
            AppRowSpec(
                title: initiative.notificationBody,
                description: status.state.label,
                accessory: .none
            ),
            AppRowSpec(
                title: Localized.Intent.nextExpected,
                value: status.nextOccurrence
                    .map { $0.formatted(date: .abbreviated, time: .shortened) } ?? Localized.Intent
                    .notScheduled,
                accessory: .none
            ),
        ]
        if let issue = status.issue {
            rows.append(AppRowSpec(
                title: Localized.Intent.schedulingIssue,
                description: issue,
                accessory: .none
            ))
        }
        if status.canCancel {
            rows.append(AppRowSpec(
                title: Localized.Intent.cancelInitiative,
                accessory: .trash,
                tone: .destructive,
                action: {
                    Task {
                        do { try await Container.shared.initiativeService().cancel(
                            id: initiative.id,
                            agentID: intent.agentID,
                            spaceID: intent.spaceID
                        ) } catch { initiativeError = error.localizedDescription }
                    }
                }
            ))
        }
        return rows
    }
}
