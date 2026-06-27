import SwiftUI

/// One selectable row in an `AppOptionPicker`. Pairs a `value` with its display
/// `label` and an optional trailing `detail` (for example a dialect or region).
/// The value doubles as identity, so values must be unique within a picker.
struct AppOption<Value: Hashable>: Identifiable {
    let value: Value
    let label: String
    let detail: String?

    var id: Value {
        value
    }

    init(_ label: String, value: Value, detail: String? = nil) {
        self.label = label
        self.value = value
        self.detail = detail
    }
}

/// A disclosure that folds out a single-select list of text options. The header
/// names the picker and summarises the current choice; each revealed row shows
/// its label, an optional trailing detail, and a checkmark on the selected one.
/// Like `AppSwitch` and `AppSegmentedControl`, it follows the value + action
/// convention: it reflects `selection` and reports taps through `onSelect`,
/// leaving state to the caller.
struct AppOptionPicker<Value: Hashable>: View {
    let title: String
    let description: String?
    let options: [AppOption<Value>]
    let selection: Value
    let onSelect: (Value) -> Void

    @Environment(\.colors) private var colors

    init(
        title: String,
        description: String? = nil,
        options: [AppOption<Value>],
        selection: Value,
        onSelect: @escaping (Value) -> Void
    ) {
        self.title = title
        self.description = description
        self.options = options
        self.selection = selection
        self.onSelect = onSelect
    }

    /// Text shown as the disclosure summary: the explicit description if
    /// provided, otherwise the label of the currently selected option.
    private var summaryText: String? {
        description ?? options.first { $0.value == selection }?.label
    }

    var body: some View {
        AppDisclosure(title, description: summaryText) {
            VStack(spacing: Spacing.n16) {
                ForEach(options) { option in
                    row(option)
                }
            }
        }
    }

    private func row(_ option: AppOption<Value>) -> some View {
        let isSelected = option.value == selection
        return Button {
            onSelect(option.value)
        } label: {
            HStack {
                Text(option.label)
                    .typography(Typography.navTab)
                    .foregroundStyle(
                        isSelected ? colors.text.standard.base : colors.text.standard.muted
                    )
                if let detail = option.detail {
                    Spacer()
                    Text(detail)
                        .typography(Typography.note)
                        .foregroundStyle(colors.text.standard.muted)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(colors.text.standard.base)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

private struct AppOptionPickerPreview: View {
    @Environment(\.colors) private var colors
    @State private var voice = "samantha"
    @State private var provider = "openai"

    private var voiceOptions: [AppOption<String>] {
        [
            AppOption("System default", value: ""),
            AppOption("Samantha", value: "samantha", detail: "American"),
            AppOption("Daniel", value: "daniel", detail: "British"),
            AppOption("Karen", value: "karen", detail: "Australian"),
        ]
    }

    private var providerOptions: [AppOption<String>] {
        [
            AppOption("OpenAI", value: "openai"),
            AppOption("Anthropic", value: "anthropic"),
            AppOption("Local", value: "local"),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.n8) {
                AppOptionPicker(title: "Voice", options: voiceOptions, selection: voice) {
                    voice = $0
                }
                AppOptionPicker(title: "Provider", options: providerOptions, selection: provider) {
                    provider = $0
                }
            }
            .padding(Spacing.n24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.surface.standard.base)
    }
}

#Preview("Light") {
    AppOptionPickerPreview()
        .resolveTheme()
}

#Preview("Dark") {
    AppOptionPickerPreview()
        .resolveTheme()
        .environment(\.colorScheme, .dark)
}
