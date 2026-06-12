import Factory
import SwiftData
import SwiftUI

struct IntentsList: View {
    @Environment(\.colors) private var colors
    @Injected(\.intentService) private var intentService

    @Query private var intents: [Intent]

    @State private var intentToDismiss: Intent?
    @State private var showDismissConfirmation = false

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
        Group {
            if intents.isEmpty {
                ContentUnavailableView(
                    Localized.Tools.No.Active.intents,
                    systemImage: "arrow.triangle.branch",
                    description: Text(Localized.Intent.EmptyState.hint)
                )
            } else {
                List {
                    ForEach(sortedIntents) { intent in
                        NavigationLink {
                            IntentDetail(intent: intent)
                                .hidesTabBar()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(intentPreview(intent.content))
                                    .typography(Typography.titleXS)
                                    .foregroundStyle(colors.text.standard.base)
                                    .lineLimit(2)
                                HStack(spacing: Spacing.n8) {
                                    Text(RelativeTimestamp.string(for: intent.updatedAt))
                                        .typography(Typography.miniLabel)
                                        .foregroundStyle(colors.text.standard.muted)
                                    if let cue = IntentDigest.summary(for: intent.snapshot) {
                                        Text(cue)
                                            .typography(Typography.miniLabel)
                                            .foregroundStyle(colors.text.standard.disabled)
                                    }
                                }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button {
                                intentToDismiss = intent
                                showDismissConfirmation = true
                            } label: {
                                Label(Localized.Ui.dismiss, systemImage: "xmark.circle")
                            }
                            .tint(.orange)
                        }
                    }
                }
                .animation(Animations.smooth, value: intents.map(\.id))
                .scrollContentBackground(.hidden)
            }
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .navigationTitle(Localized.Intents.title, style: Typography.titleXl)
        .navigationBarTitleDisplayMode(.inline)
        .alert(Localized.Ui.dismissIntent, isPresented: $showDismissConfirmation) {
            Button(Localized.Common.Actions.cancel, role: .cancel) {}
            Button(Localized.Ui.dismiss, role: .destructive) {
                if let intent = intentToDismiss {
                    Task {
                        try? await intentService.dismiss(id: intent.id)
                    }
                }
            }
        } message: {
            Text(Localized.Intent.dismissWarning)
        }
    }

    private func intentPreview(_ content: String) -> String {
        let firstLine = content.prefix(while: { $0 != "\n" })
        if firstLine.count > 60 {
            return String(firstLine.prefix(60)) + "..."
        }
        return String(firstLine)
    }
}
