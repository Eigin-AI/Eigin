import Markdown

final class PartialTableRewriter: MarkupRewriter {
    private let targetParagraph: Paragraph

    init(targetParagraph: Paragraph) {
        self.targetParagraph = targetParagraph
    }

    func visitParagraph(_ paragraph: Paragraph) -> Markup? {
        if paragraph.isIdentical(to: targetParagraph) {
            var mutableParagraph = paragraph
            mutableParagraph.replaceChildrenInRange(0 ..< paragraph.childCount, with: [])
            return mutableParagraph
        } else {
            return paragraph
        }
    }
}
