import Factory
import SwiftData
import SwiftUI

struct AgentView: View {
    @Environment(\.colors) private var colors
    @Query(sort: \Provider.createdAt) private var providers: [Provider]
    @Query private var agents: [Agent]

    private var agent: Agent? {
        agents.primary
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
            .background(colors.surface.standard.base.ignoresSafeArea())
            .tabBarPadding()
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }
}

#Preview {
    AgentView()
        .previewEnvironment()
}
