import Factory
import SwiftData
import SwiftUI

struct AgentView: View {
    @Environment(\.colors) private var colors
    @Query(sort: \Provider.createdAt) private var providers: [Provider]
    @Query private var agents: [Agent]

    private var agent: Agent? {
        agents.first
    }

    var body: some View {
        NavigationStack {
            Group {
                if let agent {
                    AgentProfile(
                        agent: agent,
                        providers: providers
                    )
                } else {
                    ContentUnavailableView(
                        "No Agent",
                        systemImage: "person.crop.circle.badge.questionmark",
                        description: Text(Localized.Onboarding.completionHint)
                    )
                }
            }
            .background(colors.background.ignoresSafeArea())
            .navigationTitle("Agent", style: Typography.largeTitle)
        }
    }
}

#Preview {
    AgentView()
        .previewEnvironment()
}
