import SwiftUI

/// Detail sheet for viewing and copying full error information.
struct ErrorDetailSheet: View {
    let error: ConnectionError

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colors) private var colors

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(colors.destructive)
                        Text(error.title)
                            .font(Typography.body.font.weight(.medium))
                            .foregroundStyle(colors.destructive)
                    }

                    DetailSection(title: "Suggestion") {
                        Text(error.suggestion)
                            .typography(Typography.body)
                            .foregroundStyle(colors.textPrimary)
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
            .background(colors.background)
            .navigationTitle("Error Details", style: Typography.largeTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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
