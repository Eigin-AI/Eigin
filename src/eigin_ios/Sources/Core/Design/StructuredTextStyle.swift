import SwiftUI
import Textual

extension InlineStyle {
    static func eigin(colors: ResolvedColors) -> InlineStyle {
        InlineStyle()
            .strong(.bold)
            .code(.monospaced, .fontScale(0.8), .foregroundColor(colors.textSecondary))
            .link(.foregroundColor(Color.accentColor))
    }
}

struct EiginHeadingStyle: StructuredText.HeadingStyle {
    func makeBody(configuration: Configuration) -> some View {
        let level = min(configuration.headingLevel, 6)
        let font: Font = switch level {
        case 1: Typography.largeTitle.font
        case 2: Typography.title.font
        default: Typography.headline.font
        }
        let textCase: Text.Case? = switch level {
        case 1, 2: .uppercase
        default: nil
        }
        configuration.label
            .font(font)
            .textCase(textCase)
            .textual.blockSpacing(.fontScaled(top: 1.6, bottom: 0.8))
    }
}
