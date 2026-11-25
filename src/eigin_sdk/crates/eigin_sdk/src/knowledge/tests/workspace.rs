use super::super::*;

#[test]
fn loads_the_apps_bundled_knowledge_without_a_format_migration() {
    fn load(
        root: &std::path::Path,
        directory: &std::path::Path,
        sources: &mut Vec<KnowledgeSource>,
    ) {
        for entry in std::fs::read_dir(directory).unwrap() {
            let path = entry.unwrap().path();
            if path.is_dir() {
                load(root, &path, sources);
            } else if path
                .extension()
                .is_some_and(|extension| extension == "firm")
            {
                let logical_path =
                    format!("bundled/{}", path.strip_prefix(root).unwrap().display());
                sources.push(KnowledgeSource {
                    id: logical_path.clone(),
                    path: logical_path,
                    content: std::fs::read_to_string(path).unwrap(),
                    read_only: true,
                });
            }
        }
    }
    let root =
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../../design/knowledge");
    let mut sources = Vec::new();
    load(&root, &root, &mut sources);
    let workspace = KnowledgeWorkspace::new(sources).unwrap();
    assert!(
        workspace
            .get_entity("thing".into(), "eigin".into())
            .is_some()
    );
    assert!(
        workspace
            .get_entity("fact".into(), "eigin_agent_has_knowledge".into())
            .is_some()
    );
    assert!(
        !workspace
            .get_related(
                "fact".into(),
                "eigin_agent_has_knowledge".into(),
                KnowledgeDirection::Outgoing
            )
            .is_empty()
    );
}

const SCHEMA: &str = r#"
schema person {
    field { name = "name" type = "string" required = true }
    field { name = "friend" type = "reference" required = false }
}
"#;

fn source(id: &str, path: &str, content: &str) -> KnowledgeSource {
    KnowledgeSource {
        id: id.into(),
        path: path.into(),
        content: content.into(),
        read_only: id == "schema",
    }
}

fn workspace() -> KnowledgeWorkspace {
    KnowledgeWorkspace::new(vec![
        source("schema", "schemas/person.firm", SCHEMA),
        source(
            "alice-row",
            "knowledge/person/alice.firm",
            r#"person alice { name = "Alice Æøå 🦀" friend = person.bob }"#,
        ),
        source(
            "bob-row",
            "knowledge/person/bob.firm",
            r#"person bob { name = "Bob" }"#,
        ),
    ])
    .unwrap()
}

#[test]
fn queries_entities_schemas_and_cross_source_relationships() {
    let workspace = workspace();
    assert_eq!(workspace.list_schemas(), ["person"]);
    assert_eq!(
        workspace.list_entities("person".into()),
        ["person.alice", "person.bob"]
    );
    let schema = workspace.get_schema("person".into()).unwrap();
    assert_eq!(schema.fields[0].name, "name");
    assert!(schema.fields[0].required);
    let alice = workspace
        .get_entity("person".into(), "alice".into())
        .unwrap();
    assert_eq!(
        alice.fields[0].value,
        KnowledgeFieldValue::String {
            value: "Alice Æøå 🦀".into()
        }
    );
    assert_eq!(
        workspace
            .find_entity_source("person".into(), "alice".into())
            .unwrap()
            .id,
        "alice-row"
    );
    assert_eq!(
        workspace.get_related(
            "person".into(),
            "alice".into(),
            KnowledgeDirection::Outgoing
        )[0]
        .id,
        "person.bob"
    );
    let KnowledgeQueryResult::Entities { entities } =
        workspace.query("from person".into()).unwrap()
    else {
        panic!("entity query")
    };
    assert_eq!(entities.len(), 2);
}

#[test]
fn serialization_and_validated_replacement_leave_committed_snapshot_unchanged() {
    let committed = workspace();
    let mut entity = committed
        .get_entity("person".into(), "alice".into())
        .unwrap();
    entity.fields[0].value = KnowledgeFieldValue::String {
        value: "Renamed".into(),
    };
    let content = committed
        .generate_entity_dsl(entity.clone(), "knowledge/person/alice.firm".into())
        .unwrap();
    let candidate = committed
        .replacing_source(source("alice-row", "knowledge/person/alice.firm", &content))
        .unwrap();
    assert_eq!(
        candidate.get_entity("person".into(), "alice".into()),
        Some(entity)
    );
    assert!(committed.sources()[1].content.contains("Alice Æøå"));
    // A failed host save can discard the candidate without any rollback operation.
    drop(candidate);
    assert!(committed.sources()[1].content.contains("Alice Æøå"));
}

#[test]
fn invalid_replacement_and_protected_edits_do_not_modify_snapshot() {
    let committed = workspace();
    assert!(matches!(
        committed.replacing_source(source(
            "alice-row",
            "knowledge/person/alice.firm",
            "person alice {}"
        )),
        Err(KnowledgeError::Build { .. })
    ));
    assert!(matches!(
        committed.removing_source("schema".into()),
        Err(KnowledgeError::ProtectedSource { .. })
    ));
    assert!(matches!(
        committed.replacing_source(source("schema", "schemas/person.firm", "")),
        Err(KnowledgeError::ProtectedSource { .. })
    ));
    assert_eq!(committed.list_entities("person".into()).len(), 2);
    let candidate = committed.removing_source("alice-row".into()).unwrap();
    assert_eq!(candidate.list_entities("person".into()), ["person.bob"]);
}

#[test]
fn source_paths_are_normalized_and_cannot_escape_the_workspace() {
    let source = source("schema", "./schemas/../schemas//person.firm", SCHEMA);
    let workspace = KnowledgeWorkspace::new(vec![source]).unwrap();
    assert_eq!(workspace.sources()[0].path, "schemas/person.firm");
    for path in [
        "/etc/passwd",
        "../secret.firm",
        "a/../../secret.firm",
        "C:\\secret.firm",
        "https://example.com/source",
        "",
        ".",
    ] {
        assert!(
            matches!(
                KnowledgeWorkspace::new(vec![self::source("schema", path, SCHEMA)]),
                Err(KnowledgeError::InvalidPath { .. })
            ),
            "{path}"
        );
    }
}

#[test]
fn duplicate_source_ids_and_normalized_paths_are_rejected() {
    for other in [
        source("schema", "different.firm", SCHEMA),
        source("different", "./schemas/person.firm", SCHEMA),
    ] {
        assert!(matches!(
            KnowledgeWorkspace::new(vec![source("schema", "schemas/person.firm", SCHEMA), other]),
            Err(KnowledgeError::DuplicateSource { .. })
        ));
    }
}

#[test]
fn missing_schema_and_invalid_query_are_explicit_errors() {
    assert!(matches!(
        KnowledgeWorkspace::new(vec![source("alice", "alice.firm", "person alice {}")]),
        Err(KnowledgeError::Build { .. })
    ));
    assert!(matches!(
        workspace().query("not a query".into()),
        Err(KnowledgeError::Query { .. })
    ));
}

#[test]
fn source_lookup_uses_the_same_id_normalization_as_the_graph() {
    let workspace = KnowledgeWorkspace::new(vec![
        source("schema", "schemas/person.firm", SCHEMA),
        source(
            "v1-row",
            "person/v1.firm",
            r#"person v1 { name = "Version" }"#,
        ),
    ])
    .unwrap();
    let entity = workspace.get_entity("person".into(), "v1".into()).unwrap();
    assert_eq!(entity.id, "person.v_1");
    assert_eq!(
        workspace
            .find_entity_source("person".into(), "v_1".into())
            .unwrap()
            .id,
        "v1-row"
    );
}

#[test]
fn dangling_references_preserve_existing_firm_behavior_without_loading_sources() {
    let candidate = workspace().removing_source("bob-row".into()).unwrap();
    assert!(
        candidate
            .get_related(
                "person".into(),
                "alice".into(),
                KnowledgeDirection::Outgoing
            )
            .is_empty()
    );
    let alice = candidate
        .get_entity("person".into(), "alice".into())
        .unwrap();
    assert_eq!(
        alice.fields[1].value,
        KnowledgeFieldValue::EntityReference {
            entity_id: "person.bob".into()
        }
    );
}
