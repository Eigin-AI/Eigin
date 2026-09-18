import Foundation

// Preview fixtures, chosen to break the data card: never shipped to production,
// but compiled into dev apps and tests where previews run.
#if DEBUG || EIGIN_DEV

/// The shapes a tool call and an error arrive in, chosen to break things —
/// the canonical fixtures the web gallery carries, kept in step with
/// `design/web/src/gallery/catalog/components/dataPayloads.ts`.
enum DataCardExamples {
    struct Example: Identifiable, Sendable {
        let label: String
        let value: DataValue
        var id: String {
            label
        }
    }

    /// A provider's error envelope. The line worth reading is nested two levels down.
    static let error = Example(label: "Error", value: DataValue.parse(#"""
    {"type":"error","error":{"type":"invalid_request_error","message":"Your credit balance is too low to access the Anthropic API. Please go to Plans & Billing to upgrade or purchase credits."},"request_id":"req_011Cbw2joumA3D193gBuVKbk"}
    """#)!)

    /// A memory write. Arrays inside objects inside arrays, mixed types, and a null.
    static let nested = Example(
        label: "Nested",
        value: .object([
            .init(key: "saved", value: .bool(true)),
            .init(key: "revision", value: .number(14)),
            .init(key: "core", value: .object([
                .init(
                    key: "identity",
                    value: .string(
                        "Keeps Friday mornings clear, and says so before the week fills."
                    )
                ),
                .init(key: "sources", value: .array([
                    .object([
                        .init(key: "note", value: .string("rituals.md")),
                        .init(key: "lines", value: .array([.number(3), .number(4), .number(11)])),
                    ]),
                    .object([
                        .init(key: "note", value: .string("2026-08-week.md")),
                        .init(key: "lines", value: .array([.number(22)])),
                    ]),
                ])),
                .init(key: "supersedes", value: .null),
            ])),
            .init(key: "tags", value: .array([.string("rhythm"), .string("calendar")])),
        ])
    )

    /// A search that found more than fits: a table 23 rows deep.
    static let longList = Example(
        label: "Long list",
        value: .object([
            .init(key: "query", value: .string("friday")),
            .init(key: "matched", value: .number(23)),
            .init(key: "hits", value: .array((0 ..< 23).map { index in
                let name = String(index + 1)
                let padded = String(repeating: "0", count: max(0, 2 - name.count)) + name
                let score = ((1 - Double(index) * 0.031) * 100).rounded() / 100
                return .object([
                    .init(key: "note", value: .string("note-\(padded).md")),
                    .init(key: "line", value: .number(Double(index % 9) * 7 + 3)),
                    .init(key: "score", value: .number(score)),
                ])
            })),
        ])
    )

    /// A list whose items disagree about their shape. No column set fits, so no table.
    static let mixedList = Example(
        label: "Mixed list",
        value: .object([
            .init(key: "source", value: .string("calendar")),
            .init(key: "entries", value: .array([
                .object([
                    .init(key: "title", value: .string("Design review")),
                    .init(key: "minutes", value: .number(45)),
                ]),
                .object([
                    .init(key: "title", value: .string("Flight to Berlin")),
                    .init(key: "location", value: .string("CPH T2")),
                    .init(key: "gate", value: .string("A14")),
                    .init(key: "boards", value: .string("07:40")),
                ]),
                .string("Bank holiday"),
                .object([
                    .init(key: "name", value: .string("Ida")),
                    .init(key: "relation", value: .string("sister")),
                    .init(key: "birthday", value: .string("09-21")),
                ]),
                .object([
                    .init(key: "title", value: .string("Dentist")),
                    .init(key: "location", value: .string("Nørrebrogade 14")),
                ]),
                .number(42),
            ])),
        ])
    )

    /// A nested object with far more fields than a fold was sized for.
    static let wideObject = Example(
        label: "Wide object",
        value: .object([
            .init(key: "model", value: .string("claude-opus-5")),
            .init(key: "status", value: .string("ready")),
            .init(key: "settings", value: .object([
                .init(key: "temperature", value: .number(1)),
                .init(key: "topP", value: .number(0.95)),
                .init(key: "topK", value: .number(0)),
                .init(key: "maxTokens", value: .number(8192)),
                .init(key: "stopSequences", value: .number(2)),
                .init(key: "streaming", value: .bool(true)),
                .init(key: "cachePrompt", value: .bool(true)),
                .init(key: "cacheTtl", value: .string("1h")),
                .init(key: "thinking", value: .string("auto")),
                .init(key: "thinkingBudget", value: .number(4096)),
                .init(key: "toolChoice", value: .string("auto")),
                .init(key: "parallelToolCalls", value: .bool(true)),
                .init(key: "maxToolRounds", value: .number(24)),
                .init(key: "systemPromptTokens", value: .number(1843)),
                .init(key: "contextWindow", value: .number(200_000)),
                .init(key: "visionEnabled", value: .bool(true)),
                .init(key: "audioEnabled", value: .bool(false)),
                .init(key: "jsonMode", value: .bool(false)),
                .init(key: "seed", value: .null),
                .init(key: "stopReason", value: .string("end_turn")),
                .init(key: "retries", value: .number(3)),
                .init(key: "retryBackoff", value: .string("exponential")),
                .init(key: "timeoutSeconds", value: .number(120)),
                .init(key: "region", value: .string("eu-central-1")),
            ])),
        ])
    )

    /// Fields whose values run to paragraphs, addresses and unbroken tokens.
    static let prose = Example(
        label: "Long text",
        value: .object([
            .init(key: "output", value: .string("""
            I went through the three notes that mention mornings and they broadly agree, though not in the way your calendar does. Two of them treat the first two hours as unassignable: rituals.md says nothing lands before ten, and the August week note repeats it almost word for word, which suggests it survived at least one attempt to schedule over it. The third is less certain. It records two Fridays where the morning was given away, both times to something that had already slipped from a Thursday, and in both cases the note afterwards reads as regret rather than as a decision.

            So the pattern is not that Friday mornings are protected. It is that they are the first thing spent when the week runs late, and the spending is reliably regretted. That is a different problem, and holding the slot open will not fix it on its own: whatever is slipping out of Thursday has to land somewhere, and if nothing changes upstream it will keep landing here.

            My suggestion is to hold the next four Friday mornings and leave the first Friday of each month alone, so there is somewhere for an overrun to go without it always being the same morning. If two of the four get taken anyway, that tells us the Thursday problem is the real one and we should look at that instead.
            """)),
            .init(
                key: "summary",
                value: .string(
                    "The agent read three notes, found agreement on the shape of the morning, and proposed holding Friday mornings open for a month. Nothing was written back: the proposal is waiting on you, and it will expire on its own if the week fills up first."
                )
            ),
            .init(key: "trace", value: .string("""
            RelayError: upstream refused the request
              at RelayClient.send (relay/client.rs:214)
              at ChatSession.turn (chat/session.rs:88)
              at main (main.rs:12)
            """)),
            .init(
                key: "source",
                value: .string(
                    "https://code.eigin.ai/dev/eigin/-/blob/main/src/eigin_relay/src/chat/session.rs#L88"
                )
            ),
            .init(
                key: "token",
                value: .string(
                    "sk-ant-api03-7HkQm2vNxZ8pLdR4tYbWfJcE6gAuS1iOqK9nMhVzX0yT3rB5wCjDlPeF"
                )
            ),
            .init(key: "note", value: .string("Fine.")),
        ])
    )

    /// A tool's input arguments. Three keys, no nesting. The case that stays boring.
    static let flat = Example(
        label: "Flat",
        value: .object([
            .init(key: "field", value: .string("identity")),
            .init(key: "value", value: .string("Keeps Friday mornings clear.")),
            .init(key: "overwrite", value: .bool(false)),
        ])
    )

    /// A calendar lookup. Every item shares a shape, so the list is a table.
    static let uniformList = Example(
        label: "List",
        value: .object([
            .init(key: "range", value: .string("2026-09-18")),
            .init(key: "events", value: .array([
                .object([
                    .init(key: "title", value: .string("Design review")),
                    .init(key: "startsAt", value: .string("09:30")),
                    .init(key: "minutes", value: .number(45)),
                    .init(key: "accepted", value: .bool(true)),
                ]),
                .object([
                    .init(key: "title", value: .string("Lunch with Ida")),
                    .init(key: "startsAt", value: .string("12:00")),
                    .init(key: "minutes", value: .number(60)),
                    .init(key: "accepted", value: .bool(true)),
                ]),
                .object([
                    .init(key: "title", value: .string("Sprint planning")),
                    .init(key: "startsAt", value: .string("14:00")),
                    .init(key: "minutes", value: .number(90)),
                    .init(key: "accepted", value: .bool(false)),
                ]),
            ])),
        ])
    )

    static var all: [Example] {
        [error, nested, longList, mixedList, wideObject, prose, flat, uniformList]
    }
}

#endif
