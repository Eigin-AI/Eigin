import Foundation
import Markdown
import SwiftUI

extension UnorderedList: BlockConvertible {
    func convert(
        attributeContainer: NSAttributeContainer,
        config: MarkdownRenderConfig
    ) -> MarkdownRenderable {
        let nodes: [ListItem] = children.compactMap { $0 as? ListItem }
        var items: [MarkdownListItem] = []
        for listItem in nodes {
            items.append(MarkdownListItem(
                children: listItem.blockConvertibleChildren.map { $0.convert(
                    attributeContainer: attributeContainer,
                    config: config
                ) },
                startsWithBold: listItem.startsWithBold,
                checkbox: listItem.checkBox
            ))
        }
        return .unorderedList(id: id, items: items, nestedLevel: nestedLevel)
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
