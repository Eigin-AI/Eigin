import Foundation

extension String {
    static func markdownListItem(length: Int, index: Int, item: String) -> String {
        String(
            format:
            NSLocalizedString(
                "markdown_list_item",
                value: "List with %1$d items, item %2$d: %3$@",
                comment: "Accessibility label describing a list item's position, the list length, and the item's text"
            ),
            length,
            index,
            item
        )
    }

    static let taskListItemChecked = NSLocalizedString(
        "a11y_task_list_item_checked",
        value: "checked",
        comment: "Accessibility suffix for a completed task list item"
    )

    static let taskListItemUnchecked = NSLocalizedString(
        "a11y_task_list_item_unchecked",
        value: "unchecked",
        comment: "Accessibility suffix for an incomplete task list item"
    )
}
