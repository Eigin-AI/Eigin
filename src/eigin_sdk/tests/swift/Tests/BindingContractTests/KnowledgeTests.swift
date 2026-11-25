import FixtureBindings
import XCTest

final class KnowledgeTests: ContractTestCase {
    func testWorkspaceQueriesAndCandidateIsolation() async {
        await check {
            let workspace = try KnowledgeWorkspace(sources: [
                KnowledgeSource(
                    id: "schema", path: "schema.firm",
                    content: "schema person { field { name = \"name\" type = \"string\" required = true } }",
                    readOnly: true
                ),
                KnowledgeSource(
                    id: "alice-row", path: "person/alice.firm",
                    content: "person alice { name = \"Alice Æøå 🦀\" }", readOnly: false
                ),
            ])
            let alice = try XCTUnwrap(workspace.getEntity(entityType: "person", id: "alice"))
            XCTAssertEqual(alice.fields[0].value, .string(value: "Alice Æøå 🦀"))
            XCTAssertEqual(workspace.findEntitySource(entityType: "person", id: "alice")?.id, "alice-row")
            guard case let .entities(entities) = try workspace.query(queryString: "from person") else {
                return XCTFail("Expected entity query results")
            }
            XCTAssertEqual(entities, [alice])
            let candidate = try workspace.removingSource(sourceId: "alice-row")
            XCTAssertEqual(candidate.listEntities(entityType: "person"), [])
            XCTAssertEqual(workspace.listEntities(entityType: "person"), ["person.alice"])
            do {
                _ = try workspace.removingSource(sourceId: "schema")
                XCTFail("Expected protected source error")
            } catch let KnowledgeError.ProtectedSource(sourceId) {
                XCTAssertEqual(sourceId, "schema")
            }
        }
    }

    func testTypedSerializationPreservesValuesAndSourceRelativePaths() async {
        await check {
            let fields: [(String, String, KnowledgeFieldValue)] = [
                ("text", "string", .string(value: "Backslash \\ Æøå 🦀")),
                ("enabled", "boolean", .boolean(value: true)),
                ("count", "integer", .integer(value: 9_007_199_254_740_993)),
                ("ratio", "float", .float(value: 1.25)),
                ("price", "currency", .currency(amount: "9007199254740993.123456789", currencyCode: "DKK")),
                ("created", "datetime", .dateTime(value: "2024-03-15T14:30:00+05:00")),
                ("file", "path", .path(value: "./data/input.txt")),
                ("owner", "reference", .entityReference(entityId: "sample.entry")),
                ("label", "reference", .fieldReference(entityId: "sample.entry", fieldId: "text")),
                ("items", "list", .list(items: [.list(items: [.integer(value: 42)])])),
            ]
            let schema = fields.map { name, type, _ in
                "field { name = \"\(name)\" type = \"\(type)\" required = true }"
            }.joined(separator: "\n")
            let workspace = try KnowledgeWorkspace(sources: [
                KnowledgeSource(id: "schema", path: "schema.firm", content: "schema sample { \(schema) }", readOnly: true),
            ])
            let entity = KnowledgeEntity(id: "sample.entry", entityType: "sample", fields: fields.map {
                KnowledgeField(name: $0.0, value: $0.2)
            })
            let path = "knowledge/sample/entry.firm"
            let content = try workspace.generateEntityDsl(entity: entity, sourcePath: path)
            let candidate = try workspace.replacingSource(source: KnowledgeSource(
                id: "host-row", path: path, content: content, readOnly: false
            ))
            guard case let .entities(entities) = try candidate.query(queryString: "from sample") else {
                return XCTFail("Expected entity query")
            }
            XCTAssertEqual(entities, [entity])
            XCTAssertEqual(candidate.findEntitySource(entityType: "sample", id: "entry")?.id, "host-row")
            XCTAssertEqual(workspace.listEntities(entityType: "sample"), [])
        }
    }

    func testInvalidAndLossyTypedValuesFailBeforeProducingSource() async {
        await check {
            let workspace = try KnowledgeWorkspace(sources: [])
            let values: [KnowledgeFieldValue] = [
                .currency(amount: "invalid", currencyCode: "DKK"),
                .currency(amount: "1.00", currencyCode: "INVALID"),
                .dateTime(value: "not-a-date"),
                .string(value: "Quoted \"text\""),
                .float(value: -1.25),
                .list(items: [.dateTime(value: "invalid")]),
            ]
            for value in values {
                let entity = KnowledgeEntity(id: "sample.entry", entityType: "sample", fields: [
                    KnowledgeField(name: "value", value: value),
                ])
                do {
                    _ = try workspace.generateEntityDsl(entity: entity, sourcePath: "sample/entry.firm")
                    XCTFail("Expected invalid entity")
                } catch let KnowledgeError.InvalidEntity(message) {
                    XCTAssertFalse(message.isEmpty)
                }
            }
            XCTAssertEqual(workspace.sources(), [])
        }
    }
}
