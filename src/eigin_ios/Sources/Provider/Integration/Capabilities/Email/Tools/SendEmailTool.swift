import Foundation

struct SendEmailTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "email_send",
        displayName: Localized.Tools.Email.send,
        defaultPermissionLevel: .ask, category: .email
    )

    let name = "email_send"
    var isSmallContext: Bool = false
    let provider: any EmailProvider

    var displayName: String {
        Self.capability.displayName
    }

    var capabilities: [ToolCapability] {
        [Self.capability]
    }

    var category: ToolCapability.Category {
        .email
    }

    var defaultPermissionLevel: ToolPermissionLevel {
        .ask
    }

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Send an email directly through the connected account, immediately and without any review step — use it only when the user has clearly asked for the message to be sent, not drafted.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "to": .init(
                        type: "string",
                        description: "Comma-separated recipient email addresses."
                    ),
                    "cc": .init(
                        type: "string",
                        description: "Comma-separated CC recipient email addresses."
                    ),
                    "subject": .init(type: "string", description: "Email subject line."),
                    "body": .init(type: "string", description: "Email body text."),
                ],
                required: ["to", "subject", "body"]
            )
        )
    }

    func disclosure(for toolCall: ToolCall) -> ToolDisclosure? {
        guard let to = ToolHelpers.stringArgument(toolCall, "to") else { return nil }
        // Include cc in the recipient line so every destination is disclosed.
        let cc = ToolHelpers.stringArgument(toolCall, "cc")
        let recipients = cc.map { "\(to), cc: \($0)" } ?? to
        // Show subject and body together so the operator reviews what's sent.
        let subject = ToolHelpers.stringArgument(toolCall, "subject")
        let body = ToolHelpers.stringArgument(toolCall, "body")
        let content = [subject, body].compactMap { $0 }.joined(separator: "\n\n")
        return ToolDisclosure(
            actionPhrase: Localized.Permission.Disclosure.sendEmailTo(recipients),
            detail: content.isEmpty ? nil : .block(content)
        )
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        let args = ToolHelpers.parseArguments(toolCall.function.arguments) ?? [:]

        var missing: [String] = []
        let toRaw = args["to"] as? String
        if toRaw == nil || toRaw!.isEmpty { missing.append("to") }
        let subject = args["subject"] as? String
        if subject == nil { missing.append("subject") }
        let body = args["body"] as? String
        if body == nil { missing.append("body") }
        guard missing.isEmpty, let toRaw, let subject, let body else {
            return ToolResult(
                toolCallID: toolCall.id,
                content: ToolHelpers.output(
                    errors: ["Missing required parameter(s): \(missing.joined(separator: ", "))"]
                ),
                isError: true
            )
        }

        let to = parseAddresses(toRaw)
        let cc = parseAddresses(args["cc"] as? String ?? "")
        let invalid = (to + cc).filter { !Self.isValidAddress($0) }
        guard invalid.isEmpty else {
            return ToolResult(
                toolCallID: toolCall.id,
                content: ToolHelpers.output(
                    errors: ["Invalid email address(es): \(invalid.joined(separator: ", "))"]
                ),
                isError: true
            )
        }

        do {
            // Mark at egress.
            let sent = try await provider.sendEmail(
                to: to, cc: cc, subject: subject, body: Watermark.mark(body)
            )
            return ToolResult(
                toolCallID: toolCall.id,
                content: ToolHelpers.output(result: sent.jsonObject.merging(
                    ["status": "sent"]
                ) { current, _ in current }),
                isError: false
            )
        } catch {
            return ToolResult(
                toolCallID: toolCall.id,
                content: ToolHelpers.output(errors: [error.localizedDescription]),
                isError: true
            )
        }
    }

    private func parseAddresses(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Loose shape check (`local@domain.tld`) — not full RFC 5322 validation,
    /// just enough to catch obvious typos before hitting the provider's API.
    private static func isValidAddress(_ address: String) -> Bool {
        address.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }
}
