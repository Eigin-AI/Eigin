import SwiftUI

struct AppTextInput: View {
    let label: String
    @Binding var text: String
    var isError: Bool = false
    var errorMessage: String = ""
    var isSecure: Bool = false

    @FocusState private var isFocused: Bool
    @State private var isHovered = false
    @Environment(\.colors) private var colors

    private var isActive: Bool {
        isFocused || !text.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.n12) {
            HStack {
                VStack(alignment: .leading, spacing: isActive ? Spacing.n4 : 0) {
                    // Single label — typography and position both animate together.
                    // The HStack centers the VStack vertically, so as the text field
                    // expands below, the label naturally rises toward the top.
                    Text(label)
                        .typography(isActive ? Typography.note : Typography.description)
                        .foregroundStyle(colors.text.standard.muted)

                    // TextField collapses to zero height when not floating, but stays
                    // in the hierarchy so @FocusState always has a view to bind to.
                    Group {
                        if isSecure {
                            SecureField("", text: $text)
                        } else {
                            TextField("", text: $text)
                        }
                    }
                    .typography(Typography.description)
                    .foregroundStyle(colors.text.standard.base)
                    .focused($isFocused)
                    .opacity(isActive ? 1 : 0)
                    .frame(height: isActive ? nil : 0)
                    .clipped()
                    .animation(Animations.smooth, value: isActive)
                }

                Spacer()

                trailingIcon
            }
            .padding(.horizontal, Sizing.Input.Px.left)
            .frame(height: Sizing.Input.height)
            .background(colors.input.standard.active)
            .overlay {
                Capsule()
                    .fill(isHovered ? colors.interaction.light.hover : .clear)
            }
            .overlay {
                Capsule()
                    .stroke(isError ? colors.interaction.border.error : .clear, lineWidth: 1)
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
            .onTapGesture { isFocused = true }
            .onHover { isHovered = $0 }
            .animation(Animations.smooth, value: isActive)
            .animation(Animations.smooth, value: isHovered)
            .animation(Animations.smooth, value: isError)

            if isError, !errorMessage.isEmpty {
                Text(errorMessage)
                    .typography(Typography.description)
                    .foregroundStyle(colors.text.standard.error)
                    .padding(.horizontal, Spacing.n24)
            }
        }
        .animation(Animations.smooth, value: isError)
    }

    private var trailingIcon: some View {
        ZStack {
            Image(systemName: "checkmark")
                .foregroundStyle(colors.icon.standard.base)
                .opacity(!text.isEmpty && !isError ? 1 : 0)

            Image(systemName: "info.circle")
                .foregroundStyle(colors.text.standard.base)
                .opacity(isError ? 1 : 0)
        }
        .frame(width: 24, height: 24)
        .animation(Animations.smooth, value: isError)
        .animation(Animations.smooth, value: text.isEmpty)
    }
}

// MARK: - Preview

#Preview {
    AppTextInputPreview()
        .resolveTheme()
}

private struct AppTextInputPreview: View {
    @State private var name = ""
    @State private var filled = "Martin Hansen"
    @State private var errorText = "A very long name that will definitely overflow the label"
    @State private var password = "ABC123"

    @Environment(\.colors) private var colors

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.n16) {
                AppTextInput(label: "Fornavn *", text: $name)
                AppTextInput(label: "Fornavn *", text: $filled)
                AppTextInput(
                    label: "Fornavn *",
                    text: $errorText,
                    isError: true,
                    errorMessage: "Det her er helt forkert."
                )
                AppTextInput(label: "Adgangskode", text: $password, isSecure: true)
            }
            .padding(Spacing.n24)
        }
        .background(colors.surface.standard.base)
    }
}
