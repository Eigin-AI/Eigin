import SwiftUI

/// Agent emoji + name centered on screen with a reactive ring that animates per call phase.
struct AgentCard: View {
    let agent: Agent
    let service: LiveCallService

    @Environment(\.colors) private var colors

    var body: some View {
        VStack(spacing: Spacing.md) {
            ZStack {
                ReactiveRing(phase: service.phase)
                    .frame(width: 140, height: 140)

                Text(agent.emoji)
                    .font(.system(size: 80))
            }

            Text(agent.name)
                .typography(Typography.title)
                .foregroundStyle(colors.textPrimary)
        }
    }
}
