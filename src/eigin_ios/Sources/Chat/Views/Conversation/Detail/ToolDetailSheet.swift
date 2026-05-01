import SwiftUI

/// Detail sheet showing a tool call's input arguments and output result.
struct ToolDetailSheet: View {
    let tool: ToolCallInfo

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colors) private var colors

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    statusRow

                    if let arguments = tool.arguments, !arguments.isEmpty {
                        DetailSection(title: "Input") {
                            DetailCodeBlock(markdown: jsonMarkdownBlock(arguments))
                        }
                    }

                    outputSection
                }
                .padding()
            }
            .background(colors.background)
            .navigationTitle(ToolRegistry.displayName(for: tool.name))
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
        HStack(spacing: Spacing.sm) {
            switch tool.status {
            case .executing:
                ProgressView().controlSize(.small)
                Text(Localized.Status.executing)
                    .font(Typography.body.weight(.medium))
                    .foregroundStyle(colors.textSecondary)
            case .awaitingPermission:
                Image(systemName: "lock.fill")
                    .foregroundStyle(colors.accent)
                Text(Localized.Permission.awaiting)
                    .font(Typography.body.weight(.medium))
                    .foregroundStyle(colors.accent)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(Localized.Status.completed)
                    .font(Typography.body.weight(.medium))
                    .foregroundStyle(colors.textSecondary)
            case .denied:
                Image(systemName: "slash.circle.fill")
                    .foregroundStyle(colors.destructive)
                Text(Localized.Permission.denied)
                    .font(Typography.body.weight(.medium))
                    .foregroundStyle(colors.destructive)
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(colors.destructive)
                Text(Localized.Status.error)
                    .font(Typography.body.weight(.medium))
                    .foregroundStyle(colors.destructive)
            }
        }
    }

    @ViewBuilder
    private var outputSection: some View {
        switch tool.status {
        case .executing:
            DetailSection(title: "Output") {
                HStack(spacing: Spacing.sm) {
                    ProgressView().controlSize(.small)
                    Text(Localized.Status.executingProgress)
                        .font(Typography.body)
                        .foregroundStyle(colors.textSecondary)
                }
            }
        case .awaitingPermission:
            DetailSection(title: "Output") {
                Text(Localized.Permission.waitingForUser)
                    .font(Typography.body)
                    .foregroundStyle(colors.textSecondary)
            }
        case .completed:
            if let result = tool.result, !result.isEmpty {
                DetailSection(title: "Output") {
                    DetailCodeBlock(markdown: jsonMarkdownBlock(result))
                }
            }
        case .denied:
            DetailSection(title: "Output") {
                Text(Localized.Permission.toolDeniedByPolicy)
                    .font(Typography.body)
                    .foregroundStyle(colors.textSecondary)
            }
        case .error(let message):
            DetailSection(title: "Output") {
                DetailCodeBlock(markdown: "```\n\(message)\n```")
                    .foregroundStyle(colors.destructive)
            }
        }
    }

    /// Maximum characters to render in a code block before truncating.
    private let codeBlockCharacterLimit = 3000

    private func jsonMarkdownBlock(_ raw: String) -> String {
        var content: String = if let data = raw.data(using: .utf8),
                                 let object = try? JSONSerialization.jsonObject(with: data),
                                 let pretty = try? JSONSerialization.data(
                                     withJSONObject: object,
                                     options: [.prettyPrinted, .sortedKeys]
                                 ),
                                 let string = String(data: pretty, encoding: .utf8)
        {
            string
        } else {
            raw
        }

        if content.count > codeBlockCharacterLimit {
            content = String(content.prefix(codeBlockCharacterLimit)) + "\n\n… (truncated)"
        }

        let lang = content == raw ? "" : "json"
        return "```\(lang)\n\(content)\n```"
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
