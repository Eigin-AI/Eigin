use eigin_tools::localize::ios::{format_params, generator, identifiers, parser};
use std::fs;
use tempfile::TempDir;

fn xcstrings(entries: &[(&str, Option<&str>, Option<&str>)]) -> String {
    let strings: String = entries
        .iter()
        .map(|(key, comment, value)| {
            let mut fields = Vec::new();
            if let Some(c) = comment {
                fields.push(format!("\"comment\": \"{c}\""));
            }
            if let Some(v) = value {
                fields.push(format!(
                    "\"localizations\": {{ \"en\": {{ \"stringUnit\": {{ \"state\": \"translated\", \"value\": \"{v}\" }} }} }}"
                ));
            }
            format!("    \"{key}\": {{ {} }}", fields.join(", "))
        })
        .collect::<Vec<_>>()
        .join(",\n");
    format!("{{ \"sourceLanguage\": \"en\", \"strings\": {{\n{strings}\n}} }}")
}

// --- idents ---

#[test]
fn pascal_cased_single_word() {
    assert_eq!(identifiers::pascal_cased("hello"), "Hello");
}

#[test]
fn pascal_cased_hyphenated() {
    assert_eq!(identifiers::pascal_cased("hello-world"), "HelloWorld");
}

#[test]
fn camel_cased_single_word() {
    assert_eq!(identifiers::camel_cased("hello"), "hello");
}

#[test]
fn camel_cased_hyphenated() {
    assert_eq!(identifiers::camel_cased("hello-world"), "helloWorld");
}

#[test]
fn sanitize_strips_invalid_chars() {
    assert_eq!(
        identifiers::sanitize_identifier("hello-world"),
        "helloworld"
    );
    assert_eq!(identifiers::sanitize_identifier("foo_bar"), "foo_bar");
}

#[test]
fn safe_enum_name_renames_type() {
    assert_eq!(identifiers::safe_enum_name("Type".to_string()), "Kind");
    assert_eq!(identifiers::safe_enum_name("Other".to_string()), "Other");
}

#[test]
fn escape_wraps_swift_keywords() {
    assert_eq!(identifiers::escape_if_needed("default"), "`default`");
    assert_eq!(identifiers::escape_if_needed("enum"), "`enum`");
    assert_eq!(identifiers::escape_if_needed("hello"), "hello");
}

// --- format_params ---

#[test]
fn counts_format_params() {
    assert_eq!(format_params::count_format_parameters("Hello %@"), 1);
    assert_eq!(format_params::count_format_parameters("%@ and %d"), 2);
    assert_eq!(format_params::count_format_parameters("100%%"), 0);
    assert_eq!(format_params::count_format_parameters("no params"), 0);
}

// --- parser + emit integration ---

#[test]
fn generates_static_var_for_no_params() {
    let dir = TempDir::new().unwrap();
    let path = dir.path().join("test.xcstrings");
    fs::write(
        &path,
        xcstrings(&[("chat.title", Some("The chat title"), Some("Chat"))]),
    )
    .unwrap();

    let entries = parser::parse(path.to_str().unwrap()).unwrap().entries;
    let output = generator::emit(&entries);

    assert!(output.contains("enum Chat {"));
    assert!(output.contains("static var title: String { Localized.get(\"chat.title\") }"));
}

#[test]
fn generates_static_func_for_params() {
    let dir = TempDir::new().unwrap();
    let path = dir.path().join("test.xcstrings");
    fs::write(
        &path,
        xcstrings(&[("agent.greeting", None, Some("Hello %@"))]),
    )
    .unwrap();

    let entries = parser::parse(path.to_str().unwrap()).unwrap().entries;
    let output = generator::emit(&entries);

    assert!(output.contains("static func greeting(_ p1: String) -> String {"));
    assert!(output.contains("String(format: Localized.get(\"agent.greeting\"), p1)"));
}

#[test]
fn includes_comment_as_doc_comment() {
    let dir = TempDir::new().unwrap();
    let path = dir.path().join("test.xcstrings");
    fs::write(
        &path,
        xcstrings(&[("chat.title", Some("The chat title"), Some("Chat"))]),
    )
    .unwrap();

    let entries = parser::parse(path.to_str().unwrap()).unwrap().entries;
    let output = generator::emit(&entries);

    assert!(output.contains("/// The chat title"));
}

#[test]
fn escapes_swift_keyword_leaf() {
    let dir = TempDir::new().unwrap();
    let path = dir.path().join("test.xcstrings");
    fs::write(&path, xcstrings(&[("chat.default", None, Some("Default"))])).unwrap();

    let entries = parser::parse(path.to_str().unwrap()).unwrap().entries;
    let output = generator::emit(&entries);

    assert!(output.contains("static var `default`: String"));
}

#[test]
fn renames_type_container_to_kind() {
    let dir = TempDir::new().unwrap();
    let path = dir.path().join("test.xcstrings");
    fs::write(
        &path,
        xcstrings(&[("chat.type.primary", None, Some("Primary"))]),
    )
    .unwrap();

    let entries = parser::parse(path.to_str().unwrap()).unwrap().entries;
    let output = generator::emit(&entries);

    assert!(output.contains("enum Kind {"));
    assert!(!output.contains("enum Type {"));
}

// --- parser skip handling ---

#[test]
fn parse_collects_skipped_keys() {
    let dir = TempDir::new().unwrap();
    let path = dir.path().join("test.xcstrings");
    // '2 CHATS' (no dot) and 'bad..key' (empty segment) are not domain.element;
    // 'chat.title' is valid.
    fs::write(
        &path,
        xcstrings(&[
            ("2 CHATS", None, Some("2 chats")),
            ("bad..key", None, Some("bad")),
            ("chat.title", Some("The chat title"), Some("Chat")),
        ]),
    )
    .unwrap();

    let result = parser::parse(path.to_str().unwrap()).unwrap();
    assert_eq!(result.entries.len(), 1);
    assert_eq!(result.entries[0].key, "chat.title");
    let skipped_keys: Vec<&str> = result.skipped.iter().map(|s| s.key.as_str()).collect();
    assert_eq!(skipped_keys.len(), 2);
    assert!(skipped_keys.contains(&"2 CHATS"));
    assert!(skipped_keys.contains(&"bad..key"));
}
