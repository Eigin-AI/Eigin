@testable import Eigin
import XCTest

final class DataCardTests: XCTestCase {
    // MARK: - Parsing

    func testParsePreservesKeyOrder() {
        let value = DataValue.parse(#"{"z": 1, "a": 2, "m": {"y": 1, "b": 2}}"#)
        XCTAssertEqual(value?.keys, ["z", "a", "m"])
        XCTAssertEqual(value?.value(forKey: "m")?.keys, ["y", "b"])
    }

    func testParseReadsEveryScalarType() {
        let value = DataValue.parse(
            #"{"t": true, "f": false, "n": null, "i": 14, "d": 0.95, "s": "text", "neg": -3}"#
        )
        XCTAssertEqual(value?.value(forKey: "t"), .bool(true))
        XCTAssertEqual(value?.value(forKey: "f"), .bool(false))
        XCTAssertEqual(value?.value(forKey: "n"), .null)
        XCTAssertEqual(value?.value(forKey: "i"), .number(14))
        XCTAssertEqual(value?.value(forKey: "d"), .number(0.95))
        XCTAssertEqual(value?.value(forKey: "s"), .string("text"))
        XCTAssertEqual(value?.value(forKey: "neg"), .number(-3))
    }

    func testParseDecodesEscapes() {
        let value = DataValue
            .parse(#"{"text": "line\nbreak \u00e5 emoji \ud83d\ude00 quote \" done"}"#)
        XCTAssertEqual(
            value?.value(forKey: "text"), .string("line\nbreak å emoji \u{1F600} quote \" done")
        )
    }

    func testParseRejectsNonJSON() {
        XCTAssertNil(DataValue.parse("invalid json"))
        XCTAssertNil(DataValue.parse(#"{"open": 1"#))
        XCTAssertNil(DataValue.parse(#"{"k": 1} trailing"#))
    }

    /// A mangled unicode escape is malformed, not a blank: the whole document
    /// is rejected so the sheet can show it as the raw text it arrived as.
    func testParseRejectsMangledEscape() {
        XCTAssertNil(DataValue.parse(#"{"a": "\uZZ11"}"#))
        XCTAssertNil(DataValue.parse(#"{"a": "\uD83D"}"#))
    }

    /// The error sheet wraps a bare primitive as `{ response: … }`, so a
    /// document rooted at anything other than an object has to survive.
    func testParseAcceptsRootPrimitivesAndArrays() {
        XCTAssertEqual(DataValue.parse("42"), .number(42))
        XCTAssertEqual(DataValue.parse("\"text\""), .string("text"))
        XCTAssertEqual(DataValue.parse("true"), .bool(true))
        XCTAssertEqual(DataValue.parse("[1, 2]"), .array([.number(1), .number(2)]))
    }

    // MARK: - Shape classification

    func testUniformColumnsAcceptsUniformRecordArrays() {
        let value = DataValue.parse(#"{"events": [{"a": 1, "b": "x"}, {"a": 2, "b": "y"}]}"#)
        XCTAssertEqual(value?.value(forKey: "events")?.uniformColumns(), ["a", "b"])
    }

    func testUniformColumnsRejectsMixedShapes() {
        let value = DataValue.parse(
            #"{"entries": [{"title": "a", "minutes": 1}, {"title": "b", "gate": "A14"}, "plain"]}"#
        )
        XCTAssertNil(value?.value(forKey: "entries")?.uniformColumns())
    }

    func testUniformColumnsRejectsObjectCells() {
        let value = DataValue.parse(#"{"rows": [{"a": {"x": 1}}, {"a": {"x": 2}}]}"#)
        XCTAssertNil(value?.value(forKey: "rows")?.uniformColumns())
    }

    func testHasBranchesTellsFlatFromNested() {
        let flat = DataValue.parse(#"{"field": "identity", "overwrite": false}"#)
        XCTAssertEqual(flat?.hasBranches, false)

        let nested = DataValue.parse(#"{"error": {"message": "timed out"}}"#)
        XCTAssertEqual(nested?.hasBranches, true)
    }

    func testScalarArrayJoinsValues() {
        let value = DataValue.parse(#"{"tags": ["rhythm", "calendar"]}"#)
        XCTAssertEqual(value?.value(forKey: "tags")?.isScalarArray, true)
        XCTAssertEqual(
            DataFormat.scalarArray(value?.value(forKey: "tags")?.arrayItems ?? []),
            "rhythm, calendar"
        )
    }

    // MARK: - Formatting

    func testFormatLabelHumanizesKeys() {
        XCTAssertEqual(DataFormat.label("request_id"), "Request id")
        XCTAssertEqual(DataFormat.label("startsAt"), "Starts at")
        XCTAssertEqual(DataFormat.label("topP"), "Top p")
        XCTAssertEqual(DataFormat.label("[3]"), "[3]")
    }

    func testFormatValueReadsTypesInWords() {
        // Localized: users of other languages get words in their language, so
        // assert against the same strings the code reads.
        XCTAssertEqual(DataFormat.value(.null), Localized.DataCard.none)
        XCTAssertEqual(DataFormat.value(.bool(true)), Localized.DataCard.yes)
        XCTAssertEqual(DataFormat.value(.bool(false)), Localized.DataCard.no)
        XCTAssertEqual(DataFormat.value(.string("")), Localized.DataCard.empty)
        XCTAssertEqual(DataFormat.value(.number(200_000)), "200000")
        XCTAssertEqual(DataFormat.value(.number(0.95)), "0.95")
    }

    func testHeadCutsAtWordBoundary() {
        let text = "one two three four five"
        XCTAssertEqual(DataFormat.head(text, limit: 14), "one two three")
        XCTAssertEqual(DataFormat.head("abcdefghij", limit: 5), "abcde")
    }

    // MARK: - Item naming

    func testItemLabelUsesNamingKeys() throws {
        let item = DataValue.parse(#"{"note": "rituals.md", "lines": [3, 4]}"#)
        XCTAssertEqual(try DataFormat.itemLabel(XCTUnwrap(item), 0), "rituals.md")
        XCTAssertEqual(item?.spentKey, "note")
    }

    func testItemLabelFallsBackToPosition() throws {
        let item = DataValue.parse(#"{"query": "friday"}"#)
        XCTAssertEqual(try DataFormat.itemLabel(XCTUnwrap(item), 4), "Item 5")
        XCTAssertEqual(item?.spentKey, nil)
    }

    func testLongNamingKeysAreIgnored() {
        let long = String(repeating: "x", count: 41)
        let named = DataValue.object([.init(key: "name", value: .string(long))])
        XCTAssertEqual(DataFormat.spentKey(named), nil)
        XCTAssertEqual(DataFormat.itemLabel(named, 0), "Item 1")
    }

    // MARK: - Prose

    func testIsProseMarksLongTextOnly() {
        XCTAssertTrue(DataFormat.isProse("word word word word word word word"))
        XCTAssertFalse(DataFormat.isProse("Fine."))
    }

    /// A joined list of values reads as prose once it is long, so it wraps
    /// under its label rather than running down the right column.
    func testIsProseJudgesJoinedListsOnRenderedText() {
        let tools = DataValue.parse(
            #"{"toolsAvailable": ["Get food details", "Get health log", "Log body measurement", "Log food"]}"#
        )
        let joined = DataFormat
            .scalarArray(tools?.value(forKey: "toolsAvailable")?.arrayItems ?? [])
        XCTAssertTrue(DataFormat.isProse(joined))
    }
}
