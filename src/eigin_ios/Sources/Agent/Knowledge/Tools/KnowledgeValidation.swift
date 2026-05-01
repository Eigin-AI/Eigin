import Foundation

enum KnowledgeValidation {
    /// Format a knowledge-related error into an actionable message, including the schema when
    /// available.
    static func formatError(
        _ error: Error,
        entityType: String,
        schema: FirmSchema? = nil
    ) -> String {
        let rawMessage = (error as? FirmError)
            .map { firmError in
                switch firmError {
                case .BuildError(let msg): msg
                case .ParseError(let msg): msg
                case .Other(let msg): msg
                default: firmError.localizedDescription
                }
            }
            ?? error.localizedDescription

        // Strip "Workspace file at <path> was invalid: " prefix.
        let cleaned: String = if let range = rawMessage.range(
            of: #"^Workspace file at .+ was invalid: "#,
            options: .regularExpression
        ) {
            String(rawMessage[range.upperBound...])
        } else {
            rawMessage
        }

        var result = cleaned
        if let schema {
            result += "\n\nSchema for '\(entityType)':\n" + formatSchema(schema)
        }
        return result
    }

    /// Render a ``FirmSchema`` as a human-readable field list.
    private static func formatSchema(_ schema: FirmSchema) -> String {
        schema.fields.map { field in
            var line = "  \(field.name): \(field.fieldType)"
            if field.required { line += " (required)" }
            if let allowed = field.allowedValues, !allowed.isEmpty {
                line += " — values: \(allowed.joined(separator: ", "))"
            }
            return line
        }.joined(separator: "\n")
    }
}
