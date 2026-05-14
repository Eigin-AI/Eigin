import SwiftUI

private extension HorizontalAlignment {
    struct ToolTextGuide: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[HorizontalAlignment.leading]
        }
    }

    static let toolText = HorizontalAlignment(ToolTextGuide.self)
}

/// Collapsible group of tool call indicators in the chat feed.
///
/// When a single tool is present, renders inline without collapse chrome.
/// Multiple tools collapse to show the last tool with a count badge;
/// tapping expands to show all tools.
struct ToolGroupView: View {
    let tools: [ToolCallInfo]

    @Environment(\.colors) private var colors
    @State private var isExpanded = false
    @State private var selectedTool: ToolCallInfo?

    private var isGrouped: Bool {
        tools.count > 1
    }

    var body: some View {
        VStack(alignment: .toolText, spacing: 0) {
            Button {
                if isGrouped {
                    withAnimation(Animations.gentle) {
                        isExpanded.toggle()
                    }
                } else if let tool = tools.first {
                    selectedTool = tool
                }
            } label: {
                HStack(spacing: 0) {
                    if isGrouped {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(colors.text.standard.muted.opacity(0.4))
                            .padding(.trailing, Spacing.n8)
                            .transition(.opacity.combined(with: .scale(scale: 0.5)))
                    }

                    if isExpanded {
                        Text(Localized.Tool.Group.toolsUsed(String(tools.count)))
                            .typography(Typography.chatMessage)
                            .foregroundStyle(colors.text.standard.muted.opacity(0.4))
                            .padding(.vertical, Spacing.n4)
                            .alignmentGuide(.toolText) { $0[.leading] }
                    } else if let last = tools.last {
                        ToolRowView(tool: last)
                            .id(last.id)
                            .transition(.blurReplace)
                            .alignmentGuide(.toolText) { $0[.leading] }
                        if isGrouped {
                            Text(verbatim: "(\(tools.count))")
                                .typography(Typography.chatMessage)
                                .foregroundStyle(colors.text.standard.muted.opacity(0.4))
                                .padding(.leading, Spacing.n4)
                                .transition(.opacity)
                                .contentTransition(.numericText())
                        }
                    }
                }
                .animation(Animations.smooth, value: isGrouped)
                .animation(Animations.smooth, value: tools.last?.id)
                .animation(Animations.smooth, value: tools.count)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(tools) { tool in
                        Button { selectedTool = tool } label: {
                            ToolRowView(tool: tool)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .alignmentGuide(.toolText) { $0[.leading] }
            }
        }
        .sheet(item: $selectedTool) { tool in
            ToolDetailSheet(tool: tool)
        }
    }
}

#Preview("Single tool") {
    ToolGroupView(tools: [
        ToolCallInfo(id: "1", name: "read_core", status: .completed),
    ])
    .padding()
    .previewEnvironment()
}

#Preview("Multiple tools") {
    ToolGroupView(tools: [
        ToolCallInfo(id: "1", name: "read_core", status: .completed),
        ToolCallInfo(id: "2", name: "edit_core", status: .completed),
        ToolCallInfo(id: "3", name: "set_presentation", status: .completed),
    ])
    .padding()
    .previewEnvironment()
}

#Preview("With executing") {
    ToolGroupView(tools: [
        ToolCallInfo(id: "1", name: "read_core", status: .completed),
        ToolCallInfo(id: "2", name: "edit_core", status: .executing),
    ])
    .padding()
    .previewEnvironment()
}
