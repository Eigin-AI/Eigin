import SwiftUI

struct TypingIndicator: View {
    @Environment(\.colors) private var colors

    var body: some View {
        Image(systemName: "ellipsis")
            .symbolEffect(.variableColor.cumulative, options: .repeating)
            .font(.title2)
            .foregroundStyle(colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
