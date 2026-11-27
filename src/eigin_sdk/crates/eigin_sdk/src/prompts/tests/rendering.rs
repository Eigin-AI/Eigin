use super::super::catalog::{PromptCatalog, PromptCatalogError};
use serde_json::json;
use std::collections::HashMap;
use std::sync::Arc;

fn greeting_catalog() -> Arc<PromptCatalog> {
    PromptCatalog::from_json(
        json!({
            "schema_version": 1,
            "templates": {
                "greeting": "Hello {{ name }}!{% if role %}\n{% include 'role' %}{% endif %}",
                "role": "Role: {{ role }}{% if note %}\nNote: {{ note }}{% endif %}"
            }
        })
        .to_string(),
    )
    .unwrap()
}

#[test]
fn renders_included_sections_only_when_their_conditions_are_nonempty() {
    let catalog = greeting_catalog();
    for (name, role, note, expected) in [
        ("Ada", "engineer", "", "Hello Ada!\nRole: engineer"),
        ("Lin", "", "hidden", "Hello Lin!"),
        (
            "Søren",
            "writer",
            "Welcome 🌍",
            "Hello Søren!\nRole: writer\nNote: Welcome 🌍",
        ),
        ("Ada", " ", "", "Hello Ada!\nRole:  "),
    ] {
        let parameters = HashMap::from([
            ("name".into(), name.into()),
            ("role".into(), role.into()),
            ("note".into(), note.into()),
        ]);
        assert_eq!(
            catalog.render("greeting".into(), parameters).unwrap(),
            expected
        );
    }
}

#[test]
fn preserves_whitespace_and_parameter_text_without_interpreting_it() {
    let catalog = PromptCatalog::from_json(json!({
        "schema_version": 1,
        "templates": {"message": "Title: {{ title }}\n{# internal comment #}Body:\t{{ body }}\r\n"}
    }).to_string()).unwrap();
    let parameters = HashMap::from([
        ("title".into(), "Søren's notes".into()),
        (
            "body".into(),
            "File: C:\\notes\\\"draft\"\n{{ literal }}".into(),
        ),
    ]);
    assert_eq!(
        catalog.render("message".into(), parameters).unwrap(),
        "Title: Søren's notes\nBody:\tFile: C:\\notes\\\"draft\"\n{{ literal }}\r\n"
    );
}

#[test]
fn preflight_checks_declared_usages_and_reports_all_mismatches() {
    let catalog = greeting_catalog();
    catalog
        .validate_usages(HashMap::from([(
            "greeting".into(),
            vec!["name".into(), "role".into(), "note".into()],
        )]))
        .unwrap();
    let error = catalog
        .validate_usages(HashMap::from([
            ("missing".into(), vec![]),
            ("greeting".into(), vec!["wrong".into()]),
        ]))
        .unwrap_err();
    assert!(matches!(error, PromptCatalogError::InvalidUsages { .. }));
    let message = error.to_string();
    assert!(message.contains("missing") && message.contains("wrong") && message.contains("name"));
}

#[test]
fn rendering_rejects_unknown_names_and_inexact_parameter_sets() {
    let catalog = PromptCatalog::from_json(
        json!({
            "schema_version": 1,
            "templates": {"greeting": "Hello {{ name }}!"}
        })
        .to_string(),
    )
    .unwrap();
    assert!(matches!(
        catalog.render("missing".into(), HashMap::new()),
        Err(PromptCatalogError::UnknownTemplate { .. })
    ));
    assert!(matches!(
        catalog.render("greeting".into(), HashMap::new()),
        Err(PromptCatalogError::InvalidParameters { .. })
    ));
    assert!(matches!(
        catalog.render(
            "greeting".into(),
            HashMap::from([
                ("name".into(), "Ada".into()),
                ("extra".into(), "unused".into()),
            ])
        ),
        Err(PromptCatalogError::InvalidParameters { .. })
    ));
    assert_eq!(
        catalog
            .render(
                "greeting".into(),
                HashMap::from([("name".into(), "".into())])
            )
            .unwrap(),
        "Hello !"
    );
}

#[test]
fn custom_catalogs_are_independent_of_each_other_and_the_default() {
    let custom = greeting_catalog();
    let empty = PromptCatalog::from_json(json!({"schema_version": 1, "templates": {}}).to_string())
        .unwrap();
    for catalog in [empty, PromptCatalog::default_catalog()] {
        assert!(matches!(
            catalog.render("greeting".into(), HashMap::new()),
            Err(PromptCatalogError::UnknownTemplate { .. })
        ));
    }
    assert!(
        custom
            .validate_usages(HashMap::from([(
                "greeting".into(),
                vec!["name".into(), "role".into(), "note".into()]
            )]))
            .is_ok()
    );
}
