import Foundation

/// What a data card needs to ask of an arbitrary JSON value: what is a leaf,
/// what can be a table, what a thing should be called. Kept apart from the
/// rendering so the rules can be read — and argued with — on their own.
extension DataValue {
    var isRecord: Bool {
        if case .object = self { return true }
        return false
    }

    /// A leaf is anything that can be shown as one value: no children to walk.
    var isLeaf: Bool {
        switch self {
        case .object, .array: false
        default: true
        }
    }

    var objectEntries: [Entry] {
        guard case .object(let entries) = self else { return [] }
        return entries
    }

    var arrayItems: [DataValue] {
        guard case .array(let items) = self else { return [] }
        return items
    }

    var count: Int {
        switch self {
        case .array(let items): items.count
        case .object(let entries): entries.count
        default: 0
        }
    }

    /// The keys of a record, minus the one already spent on its own label.
    func childKeys(excluding spent: String?) -> [String] {
        objectEntries.map(\.key).filter { $0 != spent }
    }

    func value(forKey key: String) -> DataValue? {
        objectEntries.first { $0.key == key }?.value
    }

    /// An array of objects that all carry the same keys — the one array shape
    /// a table can show honestly. `nil` for anything else.
    func uniformColumns() -> [String]? {
        let items = arrayItems
        guard !items.isEmpty else { return nil }
        var rows: [[Entry]] = []
        for item in items {
            guard item.isRecord else { return nil }
            rows.append(item.objectEntries)
        }
        let columns = rows[0].map(\.key)
        if columns.isEmpty { return nil }
        let sameShape = rows.allSatisfy { row in
            Set(row.map(\.key)) == Set(columns)
        }
        guard sameShape else { return nil }
        // A column of objects is a table of tables; that is a tree's job,
        // not a grid's.
        return rows.allSatisfy { row in
            row.allSatisfy { $0.value.isLeaf }
        } ? columns : nil
    }

    /// An array with no structure inside it: a set of values, not of records.
    var isScalarArray: Bool {
        let items = arrayItems
        return !items.isEmpty && items.allSatisfy(\.isLeaf)
    }

    /// Whether a value draws as a branch rather than as a single row.
    var isBranch: Bool {
        !isLeaf && !isScalarArray
    }

    /// Whether anything at this level can be opened.
    ///
    /// At the root, a flat document keeps no room for carets and starts at the
    /// card's own edge. Below it, a level with nothing to open keeps no caret
    /// column either — but it still steps in, by half a gutter past its
    /// parent's labels.
    var hasBranches: Bool {
        if case .array(let items) = self {
            if uniformColumns() != nil { return false }
            return items.contains(where: { item in
                let spent = item.spentKey
                let unspent = item.childKeys(excluding: spent)
                if item.isRecord, unspent.count == 1 {
                    return item.value(forKey: unspent[0])?.isBranch == true
                }
                return item.isBranch
            })
        }
        if isRecord {
            return objectEntries.contains { $0.value.isBranch }
        }
        return false
    }

    /// The keys of a record, in source order.
    var keys: [String] {
        objectEntries.map(\.key)
    }

    /// The naming key an item spent on its own label, so it is not repeated
    /// inside. See ``DataFormat/spentKey(_:)``.
    var spentKey: String? {
        DataFormat.spentKey(self)
    }
}

// MARK: - Formatting

enum DataFormat {
    /// Number text the way the design system reads it: whole numbers without a
    /// decimal point.
    static func number(_ value: Double) -> String {
        if value.isFinite, value == value.rounded(), abs(value) < 1e15 {
            let rounded = Int64(exactly: value.rounded()) ?? 0
            return String(rounded)
        }
        return String(value)
    }

    /// `request_id` and `startsAt` are how the payload spells it, not how a
    /// person reads it. Array indices keep their brackets: they are position,
    /// not a name.
    static func label(_ key: String) -> String {
        if key.hasPrefix("["), key.hasSuffix("]"), Int(key.dropFirst().dropLast()) != nil {
            return key
        }
        var spaced = ""
        var previous: Character?
        for character in key {
            if "._".contains(character) {
                spaced.append(" ")
            } else if let previous, previous.isLowercase || previous.isNumber,
                      character.isUppercase
            {
                spaced.append(" ")
                spaced.append(character)
            } else {
                spaced.append(character)
            }
            previous = character
        }
        return capitalized(spaced)
    }

    private static func capitalized(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst().lowercased()
    }

    static func value(_ item: DataValue) -> String {
        switch item {
        case .null: Localized.DataCard.none
        case .bool(let bool): bool ? Localized.DataCard.yes : Localized.DataCard.no
        case .number(let number): self.number(number)
        case .string(let string): string.isEmpty ? Localized.DataCard.empty : string
        default: ""
        }
    }

    /// Joined text for a set of values: one fact, not a branch to walk into.
    static func scalarArray(_ items: [DataValue]) -> String {
        items.map(value(_:)).joined(separator: ", ")
    }

    /// Long enough that it would not sit on one line beside its label, and so
    /// belongs underneath it. Judged on the text as rendered, so a joined
    /// list of values wraps like the prose it has become.
    ///
    /// A character count is a proxy. Measuring the text against the row's
    /// remaining room is the honest test; this approximates it at the width
    /// the card usually has.
    static func isProse(_ text: String) -> Bool {
        text.count > 30
    }

    /// Where to cut a long value: the last word boundary before the limit.
    static func head(_ text: String, limit: Int) -> String {
        let cut = String(text.prefix(limit))
        guard let space = cut.lastIndex(of: " ") else { return cut }
        let distance = cut.distance(from: cut.startIndex, to: space)
        return distance > limit / 2 ? String(cut[..<space]) : cut
    }

    // MARK: Array item naming

    /// Keys that name the thing they sit on. An array item titled
    /// "rituals.md" reads as itself; the same item called "[0]" reads as a
    /// position in a structure nobody asked about.
    private static let namingKeys = [
        "title", "name", "label", "summary", "note", "subject", "key", "id",
    ]

    /// What to call one item of an array: what it is, or failing that, where
    /// it is.
    static func itemLabel(_ item: DataValue, _ index: Int) -> String {
        if item.isRecord {
            for key in namingKeys {
                if case .string(let string) = item.value(forKey: key),
                   !string.isEmpty, string.count <= 40
                {
                    return string
                }
            }
        }
        return Localized.DataCard.itemLabel(String(index + 1))
    }

    /// The naming key an item spent on its own label, so it is not repeated
    /// inside.
    static func spentKey(_ item: DataValue) -> String? {
        guard item.isRecord else { return nil }
        for key in namingKeys {
            if case .string(let string) = item.value(forKey: key),
               !string.isEmpty, string.count <= 40
            {
                return key
            }
        }
        return nil
    }
}
