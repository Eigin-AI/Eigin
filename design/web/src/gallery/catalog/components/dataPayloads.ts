import type { Json } from "@lib";

/** The shapes a tool call and an error arrive in, chosen to break things. */
export const payloads: { id: string; label: string; about: string; value: Json }[] = [
  {
    id: "error",
    label: "Error",
    about: "A provider's error envelope. The line worth reading is nested two levels down.",
    value: {
      type: "error",
      error: {
        type: "invalid_request_error",
        message:
          "Your credit balance is too low to access the Anthropic API. Please go to Plans & Billing to upgrade or purchase credits.",
      },
      request_id: "req_011Cbw2joumA3D193gBuVKbk",
    },
  },
  {
    id: "list",
    label: "List",
    about: "A calendar lookup. Every item shares a shape, so the list is a table.",
    value: {
      range: "2026-09-18",
      events: [
        { title: "Design review", startsAt: "09:30", minutes: 45, accepted: true },
        { title: "Lunch with Ida", startsAt: "12:00", minutes: 60, accepted: true },
        { title: "Sprint planning", startsAt: "14:00", minutes: 90, accepted: false },
      ],
    },
  },
  {
    id: "nested",
    label: "Nested",
    about: "A memory write. Arrays inside objects inside arrays, mixed types, and a null.",
    value: {
      saved: true,
      revision: 14,
      core: {
        identity: "Keeps Friday mornings clear, and says so before the week fills.",
        sources: [
          { note: "rituals.md", lines: [3, 4, 11] },
          { note: "2026-08-week.md", lines: [22] },
        ],
        supersedes: null,
      },
      tags: ["rhythm", "calendar"],
    },
  },
  {
    id: "long",
    label: "Long list",
    about: "A search that found more than fits. Still a table, but 23 rows deep.",
    value: {
      query: "friday",
      matched: 23,
      hits: Array.from({ length: 23 }, (_, index) => ({
        note: `note-${String(index + 1).padStart(2, "0")}.md`,
        line: (index % 9) * 7 + 3,
        score: Number((1 - index * 0.031).toFixed(2)),
      })),
    },
  },
  {
    id: "mixed",
    label: "Mixed list",
    about: "A list whose items disagree about their shape. No column set fits, so no table.",
    value: {
      source: "calendar",
      entries: [
        { title: "Design review", minutes: 45 },
        { title: "Flight to Berlin", location: "CPH T2", gate: "A14", boards: "07:40" },
        "Bank holiday",
        { name: "Ida", relation: "sister", birthday: "09-21" },
      ],
    },
  },
  {
    id: "wide",
    label: "Wide object",
    about: "A nested object with far more fields than a fold was sized for.",
    value: {
      model: "claude-opus-5",
      status: "ready",
      settings: {
        temperature: 1,
        topP: 0.95,
        topK: 0,
        maxTokens: 8192,
        stopSequences: 2,
        streaming: true,
        cachePrompt: true,
        cacheTtl: "1h",
        thinking: "auto",
        thinkingBudget: 4096,
        toolChoice: "auto",
        parallelToolCalls: true,
        maxToolRounds: 24,
        systemPromptTokens: 1843,
        contextWindow: 200000,
        visionEnabled: true,
        audioEnabled: false,
        jsonMode: false,
        seed: null,
        stopReason: "end_turn",
        retries: 3,
        retryBackoff: "exponential",
        timeoutSeconds: 120,
        region: "eu-central-1",
      },
    },
  },
  {
    id: "prose",
    label: "Long text",
    about: "Fields whose values run to paragraphs, addresses and unbroken tokens.",
    value: {
      output:
        "I went through the three notes that mention mornings and they broadly agree, though not in the way your calendar does. Two of them treat the first two hours as unassignable: rituals.md says nothing lands before ten, and the August week note repeats it almost word for word, which suggests it survived at least one attempt to schedule over it. The third is less certain. It records two Fridays where the morning was given away, both times to something that had already slipped from a Thursday, and in both cases the note afterwards reads as regret rather than as a decision.\n\nSo the pattern is not that Friday mornings are protected. It is that they are the first thing spent when the week runs late, and the spending is reliably regretted. That is a different problem, and holding the slot open will not fix it on its own: whatever is slipping out of Thursday has to land somewhere, and if nothing changes upstream it will keep landing here.\n\nMy suggestion is to hold the next four Friday mornings and leave the first Friday of each month alone, so there is somewhere for an overrun to go without it always being the same morning. If two of the four get taken anyway, that tells us the Thursday problem is the real one and we should look at that instead.",
      summary:
        "The agent read three notes, found agreement on the shape of the morning, and proposed holding Friday mornings open for a month. Nothing was written back: the proposal is waiting on you, and it will expire on its own if the week fills up first.",
      trace:
        "RelayError: upstream refused the request\n  at RelayClient.send (relay/client.rs:214)\n  at ChatSession.turn (chat/session.rs:88)\n  at main (main.rs:12)",
      source: "https://code.eigin.ai/dev/eigin/-/blob/main/src/eigin_relay/src/chat/session.rs#L88",
      token: "sk-ant-api03-7HkQm2vNxZ8pLdR4tYbWfJcE6gAuS1iOqK9nMhVzX0yT3rB5wCjDlPeF",
      note: "Fine.",
    },
  },
  {
    id: "flat",
    label: "Flat",
    about: "A tool's input arguments. Three keys, no nesting. The case that stays boring.",
    value: { field: "identity", value: "Keeps Friday mornings clear.", overwrite: false },
  },
];
