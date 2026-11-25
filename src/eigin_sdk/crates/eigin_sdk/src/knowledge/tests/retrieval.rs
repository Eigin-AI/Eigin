use super::super::*;

fn entity(kind: &str, id: &str, fields: &[(&str, &str)]) -> KnowledgeEntity {
    KnowledgeEntity {
        id: format!("{kind}.{id}"),
        entity_type: kind.into(),
        fields: fields
            .iter()
            .map(|(name, value)| KnowledgeField {
                name: (*name).into(),
                value: KnowledgeFieldValue::String {
                    value: (*value).into(),
                },
            })
            .collect(),
    }
}

fn lexical(entity: &KnowledgeEntity, query: &str) -> f64 {
    knowledge_lexical_score(entity.clone(), entity.id.clone(), query.into())
}

#[test]
fn identity_and_body_evidence_preserve_relevance_tiers() {
    let person = entity(
        "actor",
        "user",
        &[("name", "John Doe"), ("content", "reading preferences")],
    );
    for (query, expected) in [
        ("actor.user", 2.2),
        ("user", 2.0),
        ("John Doe", 1.8),
        ("John", 1.6),
        ("reading preferences", 1.2),
        ("read pref", 0.6),
        ("reading unknown", 0.2),
        ("rea", 0.0),
        ("", 0.0),
    ] {
        assert_eq!(lexical(&person, query), expected, "{query}");
    }
    let draft = entity("note", "draft_v_1", &[]);
    for query in ["draft_v1", "draftV1"] {
        assert_eq!(lexical(&draft, query), 2.0);
    }
    assert_eq!(lexical(&draft, "note.draft_v1"), 2.2);
}

#[test]
fn lexical_tokens_preserve_unicode_and_canonical_equivalence() {
    let person = entity(
        "actor",
        "someone",
        &[("name", "Émilie Øster"), ("content", "日本語 — læsning")],
    );
    assert_eq!(lexical(&person, "e\u{301}milie øster"), 1.8);
    assert_eq!(lexical(&person, "emilie"), 0.0);
    assert_eq!(lexical(&person, "日本語 læsning"), 1.2);
    assert_eq!(lexical(&person, "ØSTER"), 1.6);
}

#[test]
fn nested_text_and_entity_references_are_coverage_not_identity() {
    let mut item = entity("note", "entry", &[]);
    item.fields.push(KnowledgeField {
        name: "links".into(),
        value: KnowledgeFieldValue::List {
            items: vec![KnowledgeFieldValue::List {
                items: vec![KnowledgeFieldValue::EntityReference {
                    entity_id: "actor.john".into(),
                }],
            }],
        },
    });
    assert_eq!(lexical(&item, "john"), 1.2);
    item.fields.push(KnowledgeField {
        name: "ignored".into(),
        value: KnowledgeFieldValue::FieldReference {
            entity_id: "actor.jane".into(),
            field_id: "name".into(),
        },
    });
    assert_eq!(lexical(&item, "jane"), 0.0);
}

#[test]
fn embedding_text_preserves_type_fields_and_grapheme_truncation() {
    let mut actor = entity("actor", "user", &[("name", "Daniel")]);
    actor.fields.push(KnowledgeField {
        name: "type".into(),
        value: KnowledgeFieldValue::Enum {
            value: "human".into(),
        },
    });
    assert_eq!(knowledge_embedding_text(actor), "Daniel, human");
    assert_eq!(
        knowledge_embedding_text(entity("thing", "eigin", &[("name", "Eigin")])),
        "Eigin"
    );
    assert_eq!(
        knowledge_embedding_text(entity(
            "fact",
            "privacy",
            &[("name", "Privacy"), ("claim", "Local first")]
        )),
        "Privacy: Local first"
    );
    assert_eq!(
        knowledge_embedding_text(entity(
            "fact",
            "privacy",
            &[("name", ""), ("claim", "Local first")]
        )),
        "Local first"
    );
    assert_eq!(
        knowledge_embedding_text(entity("note", "empty", &[])),
        "note.empty"
    );
    assert_eq!(
        knowledge_embedding_text(entity("custom", "entry", &[("a", "One"), ("b", "Two")])),
        "One Two"
    );
    let grapheme = "👩‍👩‍👧‍👦";
    let content = grapheme.repeat(501);
    assert_eq!(
        knowledge_embedding_text(entity(
            "output",
            "draft",
            &[("name", "Draft"), ("content", &content)]
        )),
        format!("Draft: {}", grapheme.repeat(500))
    );
}

#[test]
fn memory_decay_and_importance_keep_existing_weights() {
    let now = 100.0 * 86400.0;
    assert_eq!(knowledge_memory_activation(4.0, Some(now), now), 0.5);
    assert!(
        (knowledge_memory_activation(4.0, Some(now - 14.0 * 86400.0), now) - 1.0 / 3.0).abs()
            < 1e-12
    );
    assert_eq!(knowledge_memory_activation(100.0, Some(now), now), 0.8);
    assert_eq!(knowledge_memory_activation(4.0, None, now), 0.0);
    assert_eq!(knowledge_memory_boost(0.0, None, 0.5, now), 0.0);
    assert_eq!(knowledge_importance_lift(0.0), -0.25);
    assert_eq!(knowledge_importance_lift(1.0), 1.0);
    assert_eq!(
        knowledge_memory_boost(4.0, Some(now), 2.0, now),
        knowledge_memory_boost(4.0, Some(now), 1.0, now)
    );
    assert_eq!(knowledge_ranking_score(1.2, 100.0), 1.29);
    assert!(knowledge_ranking_score(1.6, -100.0) > knowledge_ranking_score(1.2, 100.0));
}

#[test]
fn cosine_handles_missing_and_incompatible_host_vectors() {
    for (left, right, expected) in [
        (vec![], vec![], 0.0),
        (vec![1.0], vec![1.0, 0.0], 0.0),
        (vec![0.0], vec![1.0], 0.0),
        (vec![1.0, 0.0], vec![0.0, 1.0], 0.0),
        (vec![1.0, 0.0], vec![1.0, 0.0], 1.0),
    ] {
        assert_eq!(knowledge_cosine_similarity(left, right), expected);
    }
}

#[test]
fn scoring_keeps_metadata_and_thresholds_on_relevance_before_limit() {
    let candidate = |id: &str, expired: bool, importance: f64| KnowledgeSearchCandidate {
        entity: entity("note", id, &[("content", "shared topic")]),
        memory: Some(KnowledgeMemory {
            source_id: format!("row-{id}"),
            chat_id: Some("chat".into()),
            embedding: vec![1.0, 0.0],
            access_count: 0.0,
            last_accessed_at: None,
            importance,
            expired,
        }),
    };
    let candidates = vec![
        candidate("z", false, 0.5),
        candidate("a", false, 0.5),
        candidate("hidden", true, 1.0),
    ];
    let scored = knowledge_score_candidates(
        candidates.clone(),
        vec![1.0, 0.0],
        Some("shared topic".into()),
        false,
        0.0,
    );
    assert_eq!(scored.len(), 2);
    assert_eq!(scored[0].relevance, 1.2);
    let ranked = knowledge_rank_results(scored.clone(), 1.2, Some(1));
    assert_eq!(ranked[0].qualified_id, "note.a");
    assert_eq!(ranked[0].source_id.as_deref(), Some("row-a"));
    assert_eq!(ranked[0].chat_id.as_deref(), Some("chat"));
    assert!(knowledge_rank_results(scored, 1.21, None).is_empty());
    assert_eq!(
        knowledge_score_candidates(candidates, vec![1.0, 0.0], None, true, 0.0).len(),
        3
    );
}

#[test]
fn shadowing_uses_specificity_and_stable_input_order_only() {
    let row =
        |id: &str, path: &str, space: Option<&str>, agent: Option<&str>| KnowledgeSourceScope {
            source_id: id.into(),
            path: path.into(),
            space_id: space.map(str::to_owned),
            agent_id: agent.map(str::to_owned),
        };
    let rows = vec![
        row("global", "knowledge/note/draft_v1.firm", None, None),
        row("agent", "knowledge/note/draft_v_1.firm", None, Some("a")),
        row(
            "space",
            "knowledge/note/note.draft_v1.firm",
            Some("s"),
            None,
        ),
        row("tie", "knowledge/note/draft_v_1.firm", Some("s"), None),
        row("other", "knowledge/note/other.firm", None, None),
    ];
    assert_eq!(
        knowledge_select_source_ids(rows, Some("s".into()), Some("a".into())),
        ["space", "other"]
    );
    assert_eq!(
        knowledge_entity_key("knowledge/actor/actor.daniel.firm".into()),
        "actor.daniel"
    );
}
