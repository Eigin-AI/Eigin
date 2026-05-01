import Foundation
import MessageUI

struct ComposeEmailRequest {
    let to: [String]
    let cc: [String]
    let bcc: [String]
    let subject: String
    let body: String
    let isHTML: Bool
}

enum ComposeEmailResult: String {
    case sent, cancelled, saved, failed
}

typealias ComposeEmailHandler = @Sendable (
    ComposeEmailRequest,
    CheckedContinuation<ComposeEmailResult, Never>
) -> Void

struct ComposeEmailTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "compose_email",
        displayName: Localized.Tools.Compose.email,
        defaultPermissionLevel: .ask, category: .external
    )

    let name = "compose_email"
    var isSmallContext: Bool = false
    var displayName: String {
        Self.capability.displayName
    }

    var capabilities: [ToolCapability] {
        [Self.capability]
    }

    var category: ToolCapability.Category {
        .external
    }

    var defaultPermissionLevel: ToolPermissionLevel {
        .ask
    }

    let onCompose: ComposeEmailHandler?

    init(onCompose: ComposeEmailHandler? = nil) {
        self.onCompose = onCompose
    }

    func definition() -> ToolDefinition {
        if isSmallContext {
            return ToolDefinition(
                name: name,
                description: "Compose an email draft.",
                parameters: JSONSchema(
                    type: "object",
                    properties: [
                        "to": .init(type: "string", description: "Comma-separated recipients."),
                        "subject": .init(type: "string", description: "Subject line."),
                        "body": .init(type: "string", description: "Email body."),
                    ],
                    required: ["to"]
                )
            )
        }
        return ToolDefinition(
            name: name,
            description: "Pre-fill an email draft for the user. The user reviews and decides whether to send or cancel.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "to": .init(
                        type: "string",
                        description: "Comma-separated recipient email addresses."
                    ),
                    "subject": .init(
                        type: "string",
                        description: "Email subject line."
                    ),
                    "body": .init(
                        type: "string",
                        description: "Email body text."
                    ),
                    "cc": .init(
                        type: "string",
                        description: "Comma-separated CC recipient email addresses."
                    ),
                    "bcc": .init(
                        type: "string",
                        description: "Comma-separated BCC recipient email addresses."
                    ),
                    "is_html": .init(
                        type: "string",
                        description: "Whether body is HTML. 'true' or 'false', defaults to 'false'."
                    ),
                ],
                required: ["to"]
            )
        )
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        let id = toolCall.id

        guard let args = ToolHelpers.parseArguments(toolCall.function.arguments) else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Invalid JSON arguments"]),
                isError: true
            )
        }

        guard let toRaw = args["to"] as? String, !toRaw.isEmpty else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Missing 'to' parameter"]),
                isError: true
            )
        }

        guard MFMailComposeViewController.canSendMail() else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Mail is not configured on this device."]),
                isError: true
            )
        }

        guard let onCompose else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers
                    .output(errors: ["Email compose is not available in this context."]),
                isError: true
            )
        }

        let to = parseAddresses(toRaw)
        let cc = parseAddresses(args["cc"] as? String ?? "")
        let bcc = parseAddresses(args["bcc"] as? String ?? "")
        let subject = args["subject"] as? String ?? ""
        let body = args["body"] as? String ?? ""
        let isHTML = (args["is_html"] as? String ?? "false").lowercased() == "true"
            || (args["is_html"] as? Bool ?? false)

        let request = ComposeEmailRequest(
            to: to, cc: cc, bcc: bcc,
            subject: subject, body: body, isHTML: isHTML
        )

        let result = await withCheckedContinuation { continuation in
            onCompose(request, continuation)
        }

        return ToolResult(
            toolCallID: id,
            content: ToolHelpers.output(result: ["status": result.rawValue]),
            isError: result == .failed
        )
    }

    private func parseAddresses(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
