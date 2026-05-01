import SwiftUI

struct ToolRowView: View {
    let tool: ToolCallInfo

    @Environment(\.colors) private var colors

    var body: some View {
        let name = displayName(tool.name)
        let suffix: String? = switch tool.status {
        case .executing, .completed: nil
        case .awaitingPermission: "awaiting permission"
        case .denied: "denied"
        case .error: "failed"
        }
        let color: Color = switch tool.status {
        case .executing: colors.textSecondary
        case .completed: colors.textSecondary.opacity(0.6)
        case .awaitingPermission: colors.accent
        case .denied, .error: colors.destructive
        }
        let isExecuting = tool.status == .executing

        Text(suffix != nil ? "\(name) \(suffix!)" : name)
            .font(Typography.body.weight(.medium))
            .foregroundStyle(color)
            .breathe(isActive: isExecuting)
            .padding(.vertical, Spacing.xs)
            .animation(Animations.smooth, value: tool.status)
    }

    private func displayName(_ name: String) -> String {
        ToolRegistry.displayName(for: name)
    }
}

// MARK: - Breathe Animation

private struct BreatheModifier: ViewModifier {
    let isActive: Bool
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isActive && isPulsing ? 0.4 : 1.0)
            .animation(
                isActive
                    ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsing
            )
            .onChange(of: isActive) { _, active in
                isPulsing = active
            }
            .onAppear {
                if isActive { isPulsing = true }
            }
    }
}

private extension View {
    func breathe(isActive: Bool) -> some View {
        modifier(BreatheModifier(isActive: isActive))
    }
}
