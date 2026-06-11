import SwiftUI

/// Detail sheet showing a tool call's input arguments and output result.
struct ToolDetailSheet: View {
    let tool: ToolCallInfo

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colors) private var colors

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.n24) {
                    statusRow

                    if let arguments = tool.arguments, !arguments.isEmpty {
                        DetailSection(title: "Input") {
                            DetailCodeBlock(
                                code: jsonCode(arguments),
                                language: jsonLanguage(arguments)
                            )
                        }
                    }

                    outputSection
                }
                .padding()
            }
            .background(colors.surface.standard.base)
            .navigationTitle(ToolRegistry.displayName(for: tool.name), style: Typography.titleXl)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Localized.Debug.done) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var statusRow: some View {
        HStack(spacing: Spacing.n8) {
            switch tool.status {
            case .executing:
                ProgressView().controlSize(.small)
                Text(Localized.Status.executing)
                    .font(Typography.body.font.weight(.medium))
                    .foregroundStyle(colors.text.standard.muted)
            case .awaitingPermission:
                Image(systemName: "lock.fill")
                    .foregroundStyle(colors.accent)
                Text(Localized.Permission.awaiting)
                    .font(Typography.body.font.weight(.medium))
                    .foregroundStyle(colors.accent)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(Localized.Status.completed)
                    .font(Typography.body.font.weight(.medium))
                    .foregroundStyle(colors.text.standard.muted)
            case .denied:
                Image(systemName: "slash.circle.fill")
                    .foregroundStyle(colors.text.standard.error)
                Text(Localized.Permission.denied)
                    .font(Typography.body.font.weight(.medium))
                    .foregroundStyle(colors.text.standard.error)
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(colors.text.standard.error)
                Text(Localized.Status.error)
                    .font(Typography.body.font.weight(.medium))
                    .foregroundStyle(colors.text.standard.error)
            }
        }
    }

    @ViewBuilder
    private var outputSection: some View {
        switch tool.status {
        case .executing:
            DetailSection(title: "Output") {
                HStack(spacing: Spacing.n8) {
                    ProgressView().controlSize(.small)
                    Text(Localized.Status.executingProgress)
                        .typography(Typography.body)
                        .foregroundStyle(colors.text.standard.muted)
                }
            }
        case .awaitingPermission:
            DetailSection(title: "Output") {
                Text(Localized.Permission.waitingForUser)
                    .typography(Typography.body)
                    .foregroundStyle(colors.text.standard.muted)
            }
        case .completed:
            if let result = tool.result, !result.isEmpty {
                DetailSection(title: "Output") {
                    DetailCodeBlock(code: jsonCode(result), language: jsonLanguage(result))
                }
            }
        case .denied:
            DetailSection(title: "Output") {
                Text(Localized.Permission.toolDeniedByPolicy)
                    .typography(Typography.body)
                    .foregroundStyle(colors.text.standard.muted)
            }
        case .error(let message):
            DetailSection(title: "Output") {
                DetailCodeBlock(code: message)
                    .foregroundStyle(colors.text.standard.error)
            }
        }
    }
}

#Preview("Completed tool") {
    ToolDetailSheet(tool: ToolCallInfo(
        id: "1",
        name: "read_core",
        status: .completed,
        arguments: "{\"field\":\"identity\"}",
        result: "{\"identity\":\"I am a helpful assistant.\"}"
    ))
    .previewEnvironment()
}

#Preview("Executing tool") {
    ToolDetailSheet(tool: ToolCallInfo(
        id: "2",
        name: "edit_core",
        status: .executing,
        arguments: "{\"field\":\"identity\",\"value\":\"Updated identity.\"}"
    ))
    .previewEnvironment()
}

#Preview("Error tool") {
    ToolDetailSheet(tool: ToolCallInfo(
        id: "3",
        name: "save_memory",
        status: .error("Connection timeout after 30s"),
        arguments: "{\"content\":\"Remember this\"}"
    ))
    .previewEnvironment()
}
