use super::*;
mod config;
mod matching;
mod policy;

fn fixture(pattern: &str, aliases: &[&str]) -> String {
    format!(
        r#"[[models]]
pattern = {pattern:?}
aliases = {aliases:?}
display_name = {pattern:?}
family = "mistral"
context_window = 1000
supports_tool_call = false
supports_reasoning = false
supports_vision = false
is_recommended = false
"#
    )
}

fn catalog(entries: Vec<String>, ranking: &[&str]) -> ModelCatalog {
    let manifest = format!(
        "schema_version = 1\nmodel_files = ['models.toml']\npreference_ranking = {ranking:?}"
    );
    let records = if entries.is_empty() {
        "models = []".to_owned()
    } else {
        entries.join("\n")
    };
    super::config::parse(&manifest, &[("models.toml", &records)]).unwrap()
}

fn strings(values: &[&str]) -> Vec<String> {
    values.iter().map(|s| s.to_string()).collect()
}
