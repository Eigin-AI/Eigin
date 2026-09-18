import SwiftUI

/// Content view for viewing full error information.
///
/// Present with the `.appSheet` modifier; the sheet header should carry the
/// error title and suggestion via the `title:` and `description:` parameters.
/// The body is the provider's own response, read out in full by a
/// ``DataCard``. There is no raw view to reveal because nothing is hidden —
/// what the payload said is on screen, and copying it is for taking elsewhere.
struct ErrorDetailSheet: View {
    let error: ConnectionError

    @State private var copied = false
    @State private var copiedReset: Task<Void, Never>?

    var body: some View {
        Group {
            // No response to read out leaves the header to carry the error on
            // its own; rendering an empty card alongside a copy control with
            // nothing to copy would promise what is not there.
            if error.rawDescription?.isEmpty == false {
                DataCard(value: payload) {
                    copyControl
                }
            }
        }
        .padding(.horizontal, Spacing.n16)
    }

    /// A provider that answers in prose has no document to read out; its whole
    /// response is the one fact there is.
    private var payload: DataValue {
        guard let raw = error.rawDescription, !raw.isEmpty else { return .object([]) }
        if let parsed = DataValue.parse(raw) {
            return parsed.isScalarArray || parsed.isLeaf
                ? .object([.init(key: "response", value: parsed)])
                : parsed
        }
        return .object([.init(key: "response", value: .string(raw))])
    }

    /// Quiet as the small print it stands beside, but set in the display
    /// face: it is a thing to press, not a sentence to read. No button chrome;
    /// the muted colour comes from the card's own footer.
    private var copyControl: some View {
        Button {
            UIPasteboard.general.string = error.rawDescription
            copiedReset?.cancel()
            copied = true
            copiedReset = Task {
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { copied = false }
            }
        } label: {
            HStack(spacing: Spacing.n8) {
                (copied ? Iconography.Functional.check : Iconography.Functional.copy)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 12, height: 12)
                Text(copied ? Localized.Ui.copied : Localized.Ui.copyRawError)
                    .typography(Typography.tag)
            }
        }
        .buttonStyle(.plain)
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

#Preview("Primitive error") {
    ErrorDetailSheet(error: ConnectionError(
        title: "Bad response",
        suggestion: "Your provider returned a response that doesn't read as JSON. It is shown below, as it arrived.",
        rawDescription: "42"
    ))
    .previewEnvironment()
}
