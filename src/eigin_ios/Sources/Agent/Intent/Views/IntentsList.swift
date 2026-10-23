import Factory
import SwiftData
import SwiftUI

struct IntentsList: View {
    @Injected(\.intentService) private var intentService

    @Query private var intents: [Intent]

    @State private var intentToDismiss: Intent?
    @State private var showDismissConfirmation = false
    @State private var showDismissError = false

    init(agentID: UUID) {
        let id = agentID
        let activeStatus = IntentStatus.active.rawValue
        _intents = Query(
            filter: #Predicate<Intent> { $0.agentID == id && $0.status == activeStatus },
            sort: \.updatedAt,
            order: .reverse
        )
    }

    /// Intents sorted by temporal relevance (most pressing first).
    private var sortedIntents: [Intent] {
        intents.sorted { $0.snapshot.relevance > $1.snapshot.relevance }
    }

    var body: some View {
        AppSecondaryScreen(title: Localized.Intents.title, fillsViewport: intents.isEmpty) {
            if intents.isEmpty {
                AppEmptyState(
                    icon: Iconography.Functional.sparkles,
                    title: Localized.Intent.EmptyState.title,
                    description: Localized.Intent.EmptyState.hint
                )
            } else {
                AppContentGroup(footnote: Localized.Intents.footnote) {
                    ForEach(Array(sortedIntents.enumerated()), id: \.element.id) { index, intent in
                        if index > 0 { RowHairline() }
                        NavigationLink {
                            IntentDetail(intent: intent).hidesTabBar()
                        } label: {
                            AppRow(AppRowSpec(
                                title: intent.content,
                                description: IntentDigest
                                    .summary(for: intent.snapshot),
                                accessory: .none
                            ))
                            .multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(Localized.Intent.dismissAction, role: .destructive) {
                                intentToDismiss = intent
                                showDismissConfirmation = true
                            }
                        }
                    }
                }
            }
        }
        .alert(Localized.Ui.dismissIntent, isPresented: $showDismissConfirmation) {
            Button(Localized.Common.Actions.cancel, role: .cancel) {}
            Button(Localized.Ui.dismiss, role: .destructive) {
                if let intent = intentToDismiss {
                    Task {
                        do { try await intentService.dismiss(id: intent.id) }
                        catch { showDismissError = true }
                    }
                }
            }
        } message: {
            Text(Localized.Intent.dismissWarning)
        }
        .alert(Localized.Intent.dismissFailed, isPresented: $showDismissError) {
            Button(Localized.Common.Actions.ok, role: .cancel) {}
        }
    }
}
