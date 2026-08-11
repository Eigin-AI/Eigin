import Foundation
import SwiftUI

struct ThematicBreakView: View {
    @Environment(\.markdownConfig) var config: MarkdownRenderConfig

    var body: some View {
        Divider()
            .foregroundColor(config.thematicBreakColor)
            .frame(height: 4)
            .padding([.top, .bottom], 8)
            .transition(.opacity)
    }
}
