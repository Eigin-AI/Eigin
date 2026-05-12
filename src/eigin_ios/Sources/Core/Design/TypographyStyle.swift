import SwiftUI

struct TypographyStyle {
    let font: Font
    let textCase: Text.Case?

    init(_ font: Font, textCase: Text.Case? = nil) {
        self.font = font
        self.textCase = textCase
    }
}

extension View {
    func typography(_ style: TypographyStyle) -> some View {
        font(style.font).textCase(style.textCase)
    }

    func navigationTitle(_ title: String, style: TypographyStyle) -> some View {
        navigationTitle(style.textCase == .uppercase ? title.uppercased() : title)
    }
}
