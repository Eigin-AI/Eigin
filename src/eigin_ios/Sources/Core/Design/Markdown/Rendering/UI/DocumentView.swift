import Foundation
import SwiftUI

/// Renders a pre-parsed `RenderableDocument`. Driven by a streaming pipeline
/// that hands over parsed documents; `MarkdownDocumentCache` produces them.
struct DocumentView: View {
    let renderableDocument: RenderableDocument
    let config: MarkdownRenderConfig

    /// Create a `DocumentView`.
    /// - Parameters:
    ///   - renderableDocument: The parsed Markdown document to render.
    ///   - config: Render configuration. Defaults to `.default`.
    init(
        renderableDocument: RenderableDocument,
        config: MarkdownRenderConfig = .default
    ) {
        self.renderableDocument = renderableDocument
        self.config = config
    }

    var body: some View {
        BlockView(renderables: renderableDocument.renderables)
            .environment(\.markdownConfig, config)
    }
}

extension EnvironmentValues {
    /// The render configuration applied to descendant Markdown views.
    @Entry var markdownConfig: MarkdownRenderConfig = .default
}
