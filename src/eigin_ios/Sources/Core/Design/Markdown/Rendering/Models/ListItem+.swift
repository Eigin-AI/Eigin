import Foundation
import Markdown

extension ListItem {
    var startsWithBold: Bool {
        child(at: 0) is Paragraph && child(at: 0)?.child(at: 0) is Strong
    }

    var checkBox: MarkdownListItem.Checkbox? {
        switch checkbox {
        case .checked: .checked
        case .unchecked: .unchecked
        case .none: nil
        }
    }
}
