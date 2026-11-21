use super::*;

#[test]
fn matching_and_version_cases() {
    let c = catalog(
        vec![
            fixture("glm-4.7", &[]),
            fixture("gpt-4.1", &[]),
            fixture("claude-sonnet-4-6", &[]),
            fixture("claude-haiku-4-5", &[]),
            fixture("canonical-model", &["var", "vendor-variant"]),
        ],
        &[],
    );
    for id in [
        "GLM-4.7",
        "GLM-4-7",
        "glm-4.7",
        "zai-org/GLM-4.7-FP8",
        "glm-4.7-awq",
        "openai/gpt-4.1",
        "berget/vendor-variant",
        "vendor-variant-20260101",
    ] {
        assert!(c.lookup(id.into()).is_some(), "{id}");
    }
    for (id, tag) in [
        ("gpt-4.1-2025-04-14", "2025-04-14"),
        ("claude-sonnet-4-6@20260217", "20260217"),
        ("claude-sonnet-4-6-20260217", "20260217"),
        ("anthropic/claude-haiku-4-5-20251001", "20251001"),
        ("var-20260101", "20260101"),
    ] {
        assert_eq!(
            c.lookup(id.into()).unwrap().version_tag.as_deref(),
            Some(tag)
        );
    }
    for id in [
        "gpt-4.1-mini",
        "unknown",
        "nested/vendor/gpt-4.1",
        "glm-4.7-fp8-awq",
        "gpt-4.1-",
        "gpt-4.1@x",
    ] {
        assert!(c.lookup(id.into()).is_none(), "{id}");
    }
    assert!(
        c.lookup("claude-sonnet-4-6".into())
            .unwrap()
            .version_tag
            .is_none()
    );
    assert_eq!(
        c.lookup("vendor-variant".into()).unwrap().matched,
        "vendor-variant"
    );
    for suffix in ["²", "Ⅷ", "一", "-万", "1️⃣", "1́", ":2026"] {
        assert!(c.lookup(format!("gpt-4.1{suffix}")).is_some());
    }
    for suffix in ["fp8", "fp16", "bf16", "int8", "int4", "awq", "gptq", "gguf"] {
        assert!(c.lookup(format!("glm-4.7-{suffix}")).is_some());
    }
}

#[test]
fn first_match_and_alias_order_cases() {
    let parent = fixture("kimi-k2", &[]);
    let sibling = fixture("kimi-k2.5", &[]);
    assert_eq!(
        catalog(vec![parent.clone(), sibling.clone()], &[])
            .lookup("kimi-k2.5".into())
            .unwrap()
            .entry
            .pattern,
        "kimi-k2"
    );
    assert_eq!(
        catalog(vec![sibling, parent], &[])
            .lookup("kimi-k2.5".into())
            .unwrap()
            .entry
            .pattern,
        "kimi-k2.5"
    );
    let first = fixture("first", &["shared"]);
    assert_eq!(
        catalog(vec![first, fixture("shared", &[])], &[])
            .lookup("shared".into())
            .unwrap()
            .entry
            .pattern,
        "first"
    );
    assert_eq!(
        catalog(
            vec![fixture("gpt-4.1", &[]), fixture("gpt-4.1-mini", &[])],
            &[]
        )
        .lookup("gpt-4.1-mini".into())
        .unwrap()
        .entry
        .pattern,
        "gpt-4.1-mini"
    );
}

#[test]
fn selection_and_distinct_rank_semantics() {
    let c = catalog(
        vec![
            fixture("gpt-4.1", &[]),
            fixture("claude-sonnet-4-6", &["alternate"]),
        ],
        &["claude-sonnet-4-6", "gpt-4.1"],
    );
    for offers in [
        vec!["gpt-4.1", "claude-sonnet-4-6"],
        vec!["unknown", "claude-sonnet-4-6"],
    ] {
        assert_eq!(
            c.best_model(strings(&offers)).as_deref(),
            Some("claude-sonnet-4-6")
        );
    }
    assert_eq!(
        c.best_model(strings(&["anthropic/claude-sonnet-4.6", "gpt-4.1"]))
            .as_deref(),
        Some("anthropic/claude-sonnet-4.6")
    );
    assert_eq!(
        c.best_model(strings(&["claude-sonnet-4-6-20260217"]))
            .as_deref(),
        Some("claude-sonnet-4-6-20260217")
    );
    assert_eq!(
        c.best_model(strings(&["unknown", "alternate"])).as_deref(),
        Some("alternate")
    );
    assert_eq!(
        c.best_model(strings(&["unknown-a", "unknown-b"]))
            .as_deref(),
        Some("unknown-a")
    );
    assert!(c.best_model(vec![]).is_none());
    assert_eq!(
        c.known_models(strings(&["unknown", "alternate", "gpt-4.1", "alternate"])),
        strings(&["alternate", "gpt-4.1", "alternate"])
    );
    assert_eq!(c.preference_rank("alternate".into()), Some(0));
    assert_eq!(
        c.best_model(strings(&["alternate", "gpt-4.1"])).as_deref(),
        Some("gpt-4.1")
    );
    assert_eq!(c.preference_rank("unknown".into()), None);
    assert_eq!(
        catalog(vec![fixture("claude-sonnet-4-6", &["alternate"])], &[])
            .preference_rank("alternate".into()),
        None
    );
}

#[test]
fn live_catalog_invariants() {
    let c = ModelCatalog::default_catalog();
    let ranking = c.preference_ranking();
    let mut seen = std::collections::HashSet::new();
    for entry in c.entries() {
        assert!(entry.context_window > 0);
        assert!(ranking.contains(&entry.pattern), "{}", entry.pattern);
        for candidate in std::iter::once(&entry.pattern).chain(&entry.aliases) {
            assert!(seen.insert(candidate.to_lowercase()), "{candidate}");
            assert_eq!(
                c.lookup(candidate.clone()).unwrap().entry,
                entry,
                "{candidate}"
            );
        }
    }
    for pattern in &ranking {
        assert!(c.lookup(pattern.clone()).is_some(), "{pattern}");
    }
    let mut offers: Vec<_> = ranking.iter().map(|p| format!("provider/{p}")).collect();
    let expected = offers.first().cloned();
    offers.reverse();
    assert_eq!(c.best_model(offers), expected);
    let prices = c.cost_terciles();
    assert!(prices.lower <= prices.upper);
    let small = catalog(vec![], &[]).cost_terciles();
    assert_eq!((small.lower, small.upper), (1.0, 15.0));
}
