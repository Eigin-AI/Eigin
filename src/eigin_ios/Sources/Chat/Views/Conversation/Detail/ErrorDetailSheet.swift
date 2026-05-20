import SwiftUI

/// Content view for viewing and copying full error information.
///
/// Present with the ``.appSheet`` modifier; this view provides only the
/// scrollable content.
struct ErrorDetailSheet: View {
    let error: ConnectionError

    @Environment(\.colors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.n24) {
            HStack(spacing: Spacing.n8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(colors.text.standard.error)
                Text(error.title)
                    .font(Typography.body.font.weight(.medium))
                    .foregroundStyle(colors.text.standard.error)
            }

            DetailSection(title: "Suggestion") {
                Text(error.suggestion)
                    .typography(Typography.body)
                    .foregroundStyle(colors.text.standard.base)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let raw = error.rawDescription {
                DetailSection(title: "Raw Error") {
                    DetailCodeBlock(code: raw)
                }
            }
        }
        .padding()
    }
}

#Preview {
    ErrorDetailSheet(error: ConnectionError(
        title: "Authentication failed",
        suggestion: "Your API key was rejected. Double-check that it's correct and hasn't expired.",
        rawDescription: "{\"error\": \"invalid_key\"}"
    ))
    .previewEnvironment()
}
