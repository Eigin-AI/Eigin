use super::super::config;

#[test]
fn parser_accepts_independent_text_and_rejects_invalid_documents() {
    let manifest =
        "schema_version = 1\nmodel_files = ['models.toml']\npreference_ranking = ['test']";
    let records = r#"[[models]]
pattern = "test"
display_name = "Test"
family = "openai"
context_window = 1000
supports_tool_call = false
supports_reasoning = false
supports_vision = true
is_recommended = false
"#;
    let c = config::parse(manifest, &[("models.toml", records)]).unwrap();
    assert_eq!(c.lookup("test".into()).unwrap().entry.context_window, 1000);
    assert!(c.lookup("gpt-4.1".into()).is_none());
    for bad in [
        manifest.replace("= 1", "= 2"),
        manifest.replace("['models.toml']", "['models.toml','models.toml']"),
        "bad TOML".into(),
    ] {
        assert!(config::parse(&bad, &[("models.toml", records)]).is_err());
    }
    assert!(config::parse(manifest, &[]).is_err());
    for bad in [
        records.replace("1000", "0"),
        records.replace("supports_vision = true", ""),
        format!("{records}\ninput_cost_per_million = -1.0"),
        format!("{records}\n{records}"),
    ] {
        assert!(config::parse(manifest, &[("models.toml", &bad)]).is_err());
    }
}
