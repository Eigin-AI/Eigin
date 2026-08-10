import SwiftUI

/// Content view for viewing full error information.
///
/// Present with the `.appSheet` modifier; the sheet header should carry the
/// error title and suggestion via the `title:` and `description:` parameters.
/// This view provides the scrollable body: a structured field breakdown when
/// the raw response is parsable JSON, followed by the raw response itself.
struct ErrorDetailSheet: View {
    let error: ConnectionError

    @State private var showsRawError = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.n24) {
            if let raw = error.rawDescription {
                if let fields = jsonFields(raw), !fields.isEmpty {
                    ErrorFieldsCard(fields: fields)
                }
                VStack(alignment: .leading, spacing: Spacing.n16) {
                    AppSubtleActionButton(
                        showsRawError ? Localized.Ui.hideRawError : Localized.Ui.showRawError,
                        icon: Image(systemName: showsRawError ? "minus" : "plus"),
                        size: .small
                    ) {
                        withAnimation(Animations.smooth) { showsRawError.toggle() }
                    }

                    if showsRawError {
                        EiginCodeBlock(code: jsonCode(raw), language: jsonLanguage(raw))
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - JSON field extraction

private func jsonFields(_ raw: String) -> [(label: String, value: String)]? {
    guard let data = raw.data(using: .utf8),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }

    var fields: [(label: String, value: String)] = []
    for key in root.keys.sorted() {
        switch root[key] {
        case let dict as [String: Any]:
            for subKey in dict.keys.sorted() {
                if let value = dict[subKey], !(value is [Any]), !(value is [String: Any]) {
                    fields.append((label: "\(key).\(subKey)", value: "\(value)"))
                }
            }
        case let value?:
            if !(value is [Any]) {
                fields.append((label: key, value: "\(value)"))
            }
        default:
            break
        }
    }
    return fields.isEmpty ? nil : fields
}

private func formatLabel(_ raw: String) -> String {
    // Replace dots and underscores with spaces, insert spaces before camelCase capitals
    var result = raw
        .replacingOccurrences(of: ".", with: " ")
        .replacingOccurrences(of: "_", with: " ")
    result = result.reduce(into: "") { acc, char in
        if char.isUppercase, let last = acc.last, last != " " {
            acc += " "
        }
        acc.append(char)
    }
    // Sentence case: lowercase all, capitalise first character
    result = result.lowercased()
    return result.prefix(1).uppercased() + result.dropFirst()
}

// MARK: - Fields card

private struct ErrorFieldsCard: View {
    let fields: [(label: String, value: String)]

    @Environment(\.colors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.n12) {
            ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                HStack(alignment: .firstTextBaseline, spacing: Spacing.n16) {
                    Text(formatLabel(field.label))
                        .typography(Typography.miniLabel)
                        .foregroundStyle(colors.text.standard.base)
                        .frame(width: 100, alignment: .leading)
                    Text(field.value)
                        .typography(Typography.description)
                        .foregroundStyle(colors.text.standard.base)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, Spacing.n24)
        .padding(.vertical, Spacing.n24)
        .background(colors.surface.standard.elevated, in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview("JSON error") {
    ErrorDetailSheet(error: ConnectionError(
        title: "Out of credits",
        suggestion: "Your provider may require updated billing. Check your provider's dashboard and try again.",
        rawDescription: "{\"type\":\"error\",\"error\":{\"type\":\"invalid_request_error\",\"message\":\"Your credit balance is too low to access the Anthropic API. Please go to Plans & Billing to upgrade or purchase credits.\"},\"request_id\":\"req_011Cbw2joumA3D193gBuVKbk\"}"
    ))
    .previewEnvironment()
}

#Preview("Plain text error") {
    ErrorDetailSheet(error: ConnectionError(
        title: "Request failed",
        suggestion: "Your provider returned an error. Tap for details.",
        rawDescription: "invalid json"
    ))
    .previewEnvironment()
}
