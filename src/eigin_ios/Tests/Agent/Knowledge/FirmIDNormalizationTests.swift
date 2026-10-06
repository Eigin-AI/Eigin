@testable import Eigin
import Foundation
import Testing

@Suite("Firm ID normalization")
struct FirmIDNormalizationTests {
    /// Vectors verified against `convert_case` 0.6 (`to_case(Case::Snake)`),
    /// the exact function firm applies to every entity ID.
    @Test(arguments: [
        ("v1", "v_1"),
        ("p1", "p_1"),
        ("draft_v1", "draft_v_1"),
        ("fooBar", "foo_bar"),
        ("HTTPRequest", "http_request"),
        ("MP3Player", "mp_3_player"),
        ("TransformationsIn3D", "transformations_in_3_d"),
        ("john_doe", "john_doe"),
        ("eigin_trust_stack_narrative_draft_v_1", "eigin_trust_stack_narrative_draft_v_1"),
        // Firm IDs can't start with a digit (tree-sitter-firm identifier is
        // `[a-zA-Z_][a-zA-Z0-9_]*`), so leading-digit inputs never reach
        // normalization from the graph in practice.
        ("hello world-Test", "hello_world_test"),
        ("output.draft_v1", "output.draft_v_1"),
        // Digits only bound against letters, never punctuation.
        ("v1.2", "v_1.2"),
        ("v1.2.3", "v_1.2.3"),
        ("2.0", "2.0"),
        ("a.1b", "a.1_b"),
        ("", ""),
    ])
    func normalizesLikeFirm(raw: String, expected: String) {
        #expect(FirmIDNormalization.normalize(raw) == expected)
        // Normalizing twice is a no-op.
        #expect(FirmIDNormalization.normalize(expected) == expected)
    }

    /// Pin: what firm actually produces at graph-build time matches
    /// ``FirmIDNormalization/normalize(_:)`` for a corpus of tricky IDs. If
    /// the vendored firm crate bumps its convert_case version and the rules
    /// shift, this catches the drift before IDs fork again (#285).
    @Test func matchesFirmGraphIDs() throws {
        let rawIDs = [
            "draft_v1", "fooBar", "HTTPRequest", "MP3player", "p1", "e_2nd", "Note2Self",
            "IOStream", "eigin_trust_stack_narrative_draft_v1",
        ]

        let session = FirmSession()
        try session.loadSource(content: BundledKnowledge.schemas, path: "bundled/schemas.firm")
        for (index, rawID) in rawIDs.enumerated() {
            let dsl = """
            note raw_\(index)_\(rawID) {
                content = "x"
            }
            """
            try session.loadSource(content: dsl, path: "test/id_\(index).firm")
        }
        try session.build()

        let listed = try session.listEntities(entityType: "note")
        let expected = Set(
            rawIDs.enumerated().map { index, rawID in
                "note.raw_\(index)_\(FirmIDNormalization.normalize(rawID))"
            }
        )
        #expect(Set(listed) == expected)
    }
}
