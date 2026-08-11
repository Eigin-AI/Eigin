import Foundation
import Markdown
import SwiftUI

extension OrderedList: BlockConvertible {
    func convert(
        attributeContainer: NSAttributeContainer,
        config: MarkdownRenderConfig
    ) -> MarkdownRenderable {
        let nodes: [ListItem] = children.compactMap { $0 as? ListItem }
        let items: [MarkdownListItem] = nodes.map { listItem in
            MarkdownListItem(
                children: listItem.blockConvertibleChildren.map { $0.convert(
                    attributeContainer: attributeContainer,
                    config: config
                ) },
                startsWithBold: listItem.startsWithBold
            )
        }
        return .orderedList(id: id, items: items, nestedLevel: nestedLevel)
    }

    private var nestedLevel: Int {
        var nestedLevel = 0
        var currentParent = parent
        while currentParent != nil {
            if currentParent is ListItemContainer {
                nestedLevel += 1
            }
            currentParent = currentParent?.parent
        }
        return nestedLevel
    }
}
