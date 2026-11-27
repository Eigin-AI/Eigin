use super::super::{catalog::PromptCatalog, template::parser};
use serde_json::json;
use std::collections::BTreeMap;

#[test]
fn rejects_invalid_documents_and_graphs() {
    for document in [
        r#"{"schema_version":2,"templates":{}}"#,
        r#"{"schema_version":1,"templates":{},"unknown":0}"#,
        r#"{"schema_version":1,"templates":{"a":"x","a":"y"}}"#,
        r#"{"schema_version":1,"templates":{"":"x"}}"#,
        r#"{"schema_version":1,"templates":{"a":"{% include 'missing' %}"}}"#,
        r#"{"schema_version":1,"templates":{"a":"{% include 'b' %}","b":"{% include 'a' %}"}}"#,
        r#"{"schema_version":1,"templates":{"a":"{{ value | upper }}"}}"#,
    ] {
        assert!(
            PromptCatalog::from_json(document.into()).is_err(),
            "{document}"
        );
    }
}

#[test]
fn rejects_excessive_depth_even_when_dependency_is_cached() {
    let mut templates = BTreeMap::from([("000".to_owned(), "end".to_owned())]);
    for i in 1..65 {
        templates.insert(format!("{i:03}"), format!("{{% include '{:03}' %}}", i - 1));
    }
    assert!(
        PromptCatalog::from_json(json!({"schema_version":1,"templates":templates}).to_string())
            .is_err()
    );
    let deeply_nested = format!("{}x{}", "{% if a %}".repeat(65), "{% endif %}".repeat(65));
    assert!(parser::parse(&deeply_nested).is_err());
}

#[test]
fn malformed_include_reports_template_and_position() {
    let error = PromptCatalog::from_json(json!({"schema_version":1,"templates":{"main":"prefix {% include \"a\" \"b\" %}", "a\" \"b":"text"}}).to_string()).unwrap_err().to_string();
    assert!(
        error.contains("main") && error.contains("byte 7"),
        "{error}"
    );
}
