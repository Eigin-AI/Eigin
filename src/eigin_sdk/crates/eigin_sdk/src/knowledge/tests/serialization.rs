use super::super::*;

fn workspace() -> KnowledgeWorkspace {
    let fields = [
        ("text", "string"),
        ("enabled", "boolean"),
        ("count", "integer"),
        ("ratio", "float"),
        ("price", "currency"),
        ("created", "datetime"),
        ("file", "path"),
        ("owner", "reference"),
        ("label", "reference"),
        ("items", "list"),
    ]
    .map(|(name, kind)| format!("field {{ name = \"{name}\" type = \"{kind}\" required = false }}"))
    .join("\n");
    KnowledgeWorkspace::new(vec![KnowledgeSource {
        id: "schema".into(), path: "schema.firm".into(), read_only: true,
        content: format!("schema sample {{ {fields} field {{ name = \"status\" type = \"enum\" allowed_values = [\"new\", \"done\"] required = false }} }}"),
    }]).unwrap()
}

#[test]
fn typed_values_survive_generation_replacement_and_query() {
    use KnowledgeFieldValue::*;
    let fields = vec![
        (
            "text",
            String {
                value: "Backslash \\ Æøå 🦀".into(),
            },
        ),
        ("enabled", Boolean { value: true }),
        (
            "count",
            Integer {
                value: 9_007_199_254_740_993,
            },
        ),
        ("ratio", Float { value: 1.25 }),
        (
            "price",
            Currency {
                amount: "9007199254740993.123456789".into(),
                currency_code: "DKK".into(),
            },
        ),
        (
            "created",
            DateTime {
                value: "2024-03-15T14:30:00+05:00".into(),
            },
        ),
        (
            "file",
            Path {
                value: "./data/input.txt".into(),
            },
        ),
        (
            "owner",
            EntityReference {
                entity_id: "sample.entry".into(),
            },
        ),
        (
            "label",
            FieldReference {
                entity_id: "sample.entry".into(),
                field_id: "text".into(),
            },
        ),
        (
            "status",
            Enum {
                value: "done".into(),
            },
        ),
        (
            "items",
            List {
                items: vec![
                    List {
                        items: vec![Integer { value: 42 }, Integer { value: 43 }],
                    },
                    List {
                        items: vec![Integer { value: 7 }],
                    },
                ],
            },
        ),
    ];
    let entity = KnowledgeEntity {
        id: "sample.entry".into(),
        entity_type: "sample".into(),
        fields: fields
            .into_iter()
            .map(|(name, value)| KnowledgeField {
                name: name.into(),
                value,
            })
            .collect(),
    };
    let committed = workspace();
    let content = committed
        .generate_entity_dsl(entity.clone(), "sample/entry.firm".into())
        .unwrap();
    let candidate = committed
        .replacing_source(KnowledgeSource {
            id: "host-row".into(),
            path: "sample/entry.firm".into(),
            content,
            read_only: false,
        })
        .unwrap();
    let KnowledgeQueryResult::Entities { entities } =
        candidate.query("from sample".into()).unwrap()
    else {
        panic!("expected entity query")
    };
    assert_eq!(entities, vec![entity.clone()]);
    let regenerated = candidate
        .generate_entity_dsl(entities[0].clone(), "sample/entry.firm".into())
        .unwrap();
    let next = candidate
        .replacing_source(KnowledgeSource {
            id: "host-row".into(),
            path: "sample/entry.firm".into(),
            content: regenerated,
            read_only: false,
        })
        .unwrap();
    assert_eq!(
        next.get_entity("sample".into(), "entry".into()),
        Some(entity)
    );
    assert_eq!(
        candidate
            .find_entity_source("sample".into(), "entry".into())
            .unwrap()
            .id,
        "host-row"
    );
    assert!(committed.list_entities("sample".into()).is_empty());
}

#[test]
fn timestamps_retain_the_existing_minute_precision_contract() {
    let committed = workspace();
    let mut entity = KnowledgeEntity {
        id: "sample.entry".into(),
        entity_type: "sample".into(),
        fields: vec![KnowledgeField {
            name: "created".into(),
            value: KnowledgeFieldValue::DateTime {
                value: "2024-03-15T14:30:42.123+05:00".into(),
            },
        }],
    };
    let content = committed
        .generate_entity_dsl(entity.clone(), "sample/entry.firm".into())
        .unwrap();
    let candidate = committed
        .replacing_source(KnowledgeSource {
            id: "row".into(),
            path: "sample/entry.firm".into(),
            content,
            read_only: false,
        })
        .unwrap();
    entity.fields[0].value = KnowledgeFieldValue::DateTime {
        value: "2024-03-15T14:30:00+05:00".into(),
    };
    assert_eq!(
        candidate.get_entity("sample".into(), "entry".into()),
        Some(entity)
    );
}

#[test]
fn invalid_typed_values_fail_generation_without_changing_the_workspace() {
    use KnowledgeFieldValue::*;
    let committed = workspace();
    for value in [
        Currency {
            amount: "not-a-number".into(),
            currency_code: "DKK".into(),
        },
        Currency {
            amount: "1.00".into(),
            currency_code: "INVALID".into(),
        },
        DateTime {
            value: "2024-99-99T00:00:00Z".into(),
        },
        List {
            items: vec![DateTime {
                value: "not-a-date".into(),
            }],
        },
        String {
            value: "Quoted \"text\"".into(),
        },
        Float { value: -1.25 },
        Integer { value: -42 },
        Float { value: f64::NAN },
        DateTime {
            value: "2024-03-15T14:30:00+05:30".into(),
        },
        List {
            items: vec![Integer { value: 1 }, Boolean { value: true }],
        },
    ] {
        let entity = KnowledgeEntity {
            id: "sample.invalid".into(),
            entity_type: "sample".into(),
            fields: vec![KnowledgeField {
                name: "items".into(),
                value,
            }],
        };
        assert!(matches!(
            committed.generate_entity_dsl(entity, "sample/invalid.firm".into()),
            Err(KnowledgeError::InvalidEntity { .. })
        ));
    }
    assert!(committed.list_entities("sample".into()).is_empty());
}
