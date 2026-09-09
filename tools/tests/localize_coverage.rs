use eigin_tools::config;
use eigin_tools::localize;
use std::fs;

/// Regression: the committed catalog must pass its own coverage check.
///
/// Every key with a localization must be translated for each required
/// language. Catches the #229 failure mode — a key shipped with `en` but no
/// `da` — before it lands.
#[test]
fn catalog_passes_coverage_check() {
    let root = config::repo_root().unwrap();
    let passed = localize::check_all(&root, None).unwrap();
    assert!(
        passed,
        "committed localizable catalog has untranslated required-language keys"
    );
}

/// The committed allowlist must parse and reference real keys.
#[test]
fn allowlist_parses_and_references_existing_keys() {
    let root = config::repo_root().unwrap();
    let cfg = config::load(&root).unwrap();
    let ios = cfg
        .tools
        .platforms
        .get("ios")
        .expect("ios platform configured");
    let loc = ios.localize.as_ref().expect("ios localize configured");
    let allowlist_path = loc.allowlist.as_ref().expect("allowlist configured");

    let allowlist = localize::allowlist::load(&root, allowlist_path).unwrap();

    if allowlist.keys.is_empty() {
        return; // empty allowlist is fine
    }

    // Load the catalog so we can assert each allowlisted key actually exists.
    let catalog_path = format!("{root}/{}", loc.source);
    let catalog: serde_json::Value =
        serde_json::from_str(&fs::read_to_string(&catalog_path).unwrap()).unwrap();
    let strings = catalog["strings"].as_object().unwrap();

    for key in &allowlist.keys {
        assert!(
            strings.contains_key(key),
            "allowlisted key '{key}' does not exist in the catalog"
        );
    }
}
