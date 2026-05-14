import SwiftUI
import Textual

extension InlineStyle {
    static func eigin(colors: ResolvedColors) -> InlineStyle {
        InlineStyle()
            .strong(.bold)
            .code(.monospaced, .fontScale(0.8), .foregroundColor(colors.text.standard.muted))
            .link(.foregroundColor(Color.accentColor))
    }
}

struct EiginHeadingStyle: StructuredText.HeadingStyle {
    func makeBody(configuration: Configuration) -> some View {
        let level = min(configuration.headingLevel, 6)
        let font: Font = switch level {
        case 1: Typography.titleXl.font
        case 2: Typography.titleL.font
        case 3: Typography.titleM.font
        default: Typography.titleS.font
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
