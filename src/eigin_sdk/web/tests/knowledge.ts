import {
  KnowledgeWorkspace,
  KnowledgeDirection,
  KnowledgeError,
  KnowledgeFieldValue,
  KnowledgeQueryResult,
  knowledgeScoreCandidates,
  knowledgeRankResults,
  knowledgeEmbeddingText,
  knowledgeSelectSourceIds,
} from "./generated";

function assert(condition: boolean, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

export function knowledgeWorkspaceContract() {
  const workspace = new KnowledgeWorkspace([
    {
      id: "schema",
      path: "schema.firm",
      readOnly: true,
      content:
        'schema person { field { name = "name" type = "string" required = true } field { name = "friend" type = "reference" required = false } }',
    },
    {
      id: "alice-row",
      path: "people/alice.firm",
      readOnly: false,
      content: 'person alice { name = "Alice Æøå 🦀" friend = person.bob }',
    },
    {
      id: "bob-row",
      path: "people/bob.firm",
      readOnly: false,
      content: 'person bob { name = "Bob" }',
    },
  ]);
  const alice = workspace.getEntity("person", "alice");
  assert(alice !== undefined, "Missing entity");
  assert(
    KnowledgeFieldValue.String.instanceOf(alice.fields[0].value),
    "Lost field variant",
  );
  assert(alice.fields[0].value.inner.value === "Alice Æøå 🦀", "Lost Unicode");
  assert(
    workspace.findEntitySource("person", "alice")?.id === "alice-row",
    "Lost source identity",
  );
  assert(
    workspace.getRelated("person", "alice", KnowledgeDirection.Outgoing)[0]
      .id === "person.bob",
    "Lost relationship",
  );
  const result = workspace.query("from person");
  assert(
    KnowledgeQueryResult.Entities.instanceOf(result),
    "Wrong query variant",
  );
  assert(result.inner.entities.length === 2, "Wrong result count");
  const scored = knowledgeScoreCandidates(
    [
      {
        entity: alice,
        memory: {
          sourceId: "alice-row",
          embedding: [1, 0],
          accessCount: 0,
          lastAccessedAt: undefined,
          importance: 0.5,
          expired: false,
          chatId: "chat",
        },
      },
    ],
    [1, 0],
    "alice",
    false,
    0,
  );
  assert(
    scored.length === 1 && scored[0].relevance === 2,
    "Identity tier changed",
  );
  assert(
    scored[0].sourceId === "alice-row" && scored[0].chatId === "chat",
    "Lost memory metadata",
  );
  assert(
    knowledgeRankResults(scored, 2.1, undefined).length === 0,
    "Threshold used boosted score",
  );
  assert(
    knowledgeEmbeddingText(alice) === "Alice Æøå 🦀",
    "Embedding text changed",
  );
  const winners = knowledgeSelectSourceIds(
    [
      {
        sourceId: "global",
        path: "knowledge/person/alice.firm",
        spaceId: undefined,
        agentId: undefined,
      },
      {
        sourceId: "scoped",
        path: "knowledge/person/alice.firm",
        spaceId: "space",
        agentId: undefined,
      },
    ],
    "space",
    undefined,
  );
  assert(
    winners.length === 1 && winners[0] === "scoped",
    "Scope precedence changed",
  );
  const source = workspace.findEntitySource("person", "alice")!;
  const candidate = workspace.replacingSource({
    ...source,
    content: workspace.generateEntityDsl(alice, source.path),
  });
  assert(
    candidate.getEntity("person", "alice")?.id === alice.id,
    "Serialization round trip failed",
  );
  const removed = workspace.removingSource("bob-row");
  assert(
    removed.listEntities("person").length === 1,
    "Candidate removal failed",
  );
  assert(
    workspace.listEntities("person").length === 2,
    "Candidate changed committed graph",
  );
  try {
    workspace.removingSource("schema");
    throw new Error("Protected source was removed");
  } catch (error) {
    assert(
      KnowledgeError.ProtectedSource.instanceOf(error),
      "Lost protected-source error",
    );
  }
  try {
    new KnowledgeWorkspace([
      { id: "bad", path: "../outside.firm", content: "", readOnly: false },
    ]);
    throw new Error("Escaping path was accepted");
  } catch (error) {
    assert(
      KnowledgeError.InvalidPath.instanceOf(error),
      "Lost invalid-path error",
    );
  }
}
