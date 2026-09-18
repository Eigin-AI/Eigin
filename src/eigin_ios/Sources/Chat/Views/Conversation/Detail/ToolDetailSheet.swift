import SwiftUI

/// Detail sheet showing a tool call's input arguments and output result, read
/// out as facts by ``DataCard``.
///
/// Present with the `.appSheet` modifier; the header carries the tool's
/// display name and its one-sentence description.
///
/// It reads in the order the call happened: what it was asked, what came
/// back, and where it got to. The input is always there when the call carries
/// arguments; the output appears only when there is something to show, so a
/// call still running does not carry an empty block waiting to be filled.
///
/// The status is the footnote of whichever card is last, so it reads as a
/// remark about that card rather than as a line of its own: under the input
/// while the call is still going, and under the output once there is one. A
/// call that finished with nothing to return says so here rather than in an
/// empty output block, and a failed one leaves the reason to the card below.
struct ToolDetailSheet: View {
    let tool: ToolCallInfo

    @Environment(\.colors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: Sizing.PageLayout.gap) {
            if let output = outputValue {
                if let input = inputValue {
                    // The status belongs to the output once there is one, so
                    // the input card carries no footer of its own.
                    DataCard(value: input, label: Localized.ToolDetail.input)
                }
                DataCard(
                    value: output,
                    label: tool.status.isError
                        ? Localized.Status.error : Localized.ToolDetail.output,
                    footer: { statusLine }
                )
            } else {
                if let input = inputValue {
                    DataCard(
                        value: input,
                        label: Localized.ToolDetail.input,
                        footer: { statusLine }
                    )
                }
            }
        }
        .padding(.horizontal, Spacing.n16)
    }

    // MARK: - Status

    private var statusLine: some View {
        AppStatusLine(state: statusState, label: statusLabel)
    }

    /// Status is the same vocabulary a connection uses: a dot and a word.
    /// Green is done, amber wants something from you, red is a call that did
    /// not run, and a running call pulses.
    private var statusState: ConnectionState {
        switch tool.status {
        case .executing: .connecting
        case .awaitingPermission: .attention
        case .completed: .connected
        case .denied: .unavailable
        case .error: .unavailable
        }
    }

    private var statusLabel: String {
        switch tool.status {
        case .executing:
            Localized.Status.executing
        case .awaitingPermission:
            Localized.Permission.awaiting
        case .completed:
            hasResult ? Localized.Status.completed : Localized.ToolDetail.completedNoOutput
        case .denied:
            Localized.ToolDetail.deniedByUser
        case .error:
            Localized.ToolDetail.failed
        }
    }

    // MARK: - Payloads

    private var hasResult: Bool {
        guard let result = tool.result else { return false }
        return !result.isEmpty
    }

    /// A payload that does not read as JSON is still a fact: one of them.
    private func payload(_ raw: String?) -> DataValue? {
        guard let raw, !raw.isEmpty else { return nil }
        return DataValue.parse(raw) ?? .object([.init(key: "response", value: .string(raw))])
    }

    private var inputValue: DataValue? {
        payload(tool.arguments)
    }

    /// Only two states have anything to show: a result, or why there is none.
    private var outputValue: DataValue? {
        switch tool.status {
        case .completed:
            hasResult ? payload(tool.result) : nil
        case .error(let message):
            .object([.init(key: "error", value: .string(message))])
        case .executing, .awaitingPermission, .denied:
            nil
        }
    }
}

private extension ToolEventStatus {
    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

#Preview("Completed tool") {
    ToolDetailSheet(tool: ToolCallInfo(
        id: "1",
        name: "edit_core",
        status: .completed,
        arguments: #"{"field":"identity","value":"Keeps Friday mornings clear, and says so before the week fills.","overwrite":false}"#,
        result: #"{"saved":true,"revision":14,"supersedes":null}"#
    ))
    .previewEnvironment()
}

#Preview("Completed with no output") {
    ToolDetailSheet(tool: ToolCallInfo(
        id: "2",
        name: "read_core",
        status: .completed,
        arguments: #"{"field":"identity"}"#,
        result: ""
    ))
    .previewEnvironment()
}

#Preview("Executing tool") {
    ToolDetailSheet(tool: ToolCallInfo(
        id: "3",
        name: "edit_core",
        status: .executing,
        arguments: #"{"field":"identity","value":"Updated identity."}"#
    ))
    .previewEnvironment()
}

#Preview("Awaiting permission") {
    ToolDetailSheet(tool: ToolCallInfo(
        id: "4",
        name: "web_search",
        status: .awaitingPermission,
        arguments: #"{"query":"friday mornings"}"#
    ))
    .previewEnvironment()
}

#Preview("Denied tool") {
    ToolDetailSheet(tool: ToolCallInfo(
        id: "5",
        name: "web_search",
        status: .denied,
        arguments: #"{"query":"friday mornings"}"#
    ))
    .previewEnvironment()
}

#Preview("Error tool") {
    ToolDetailSheet(tool: ToolCallInfo(
        id: "6",
        name: "save_memory",
        status: .error("Connection timeout after 30s"),
        arguments: #"{"content":"Remember this"}"#
    ))
    .previewEnvironment()
}
