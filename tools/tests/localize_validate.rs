use eigin_tools::localize::ios::validator::validate;
use std::fs;
use tempfile::TempDir;

fn make_localized_swift(keys: &[&str]) -> String {
    let gets = keys
        .iter()
        .map(|k| format!("    static var x: String {{ Localized.get(\"{k}\") }}"))
        .collect::<Vec<_>>()
        .join("\n");
    format!("enum Localized {{\n{gets}\n}}\n")
}

fn write_source(dir: &TempDir, filename: &str, content: &str) {
    fs::write(dir.path().join(filename), content).unwrap();
}

#[test]
fn passes_when_all_keys_valid() {
    let src = TempDir::new().unwrap();
    let output_dir = TempDir::new().unwrap();

    let localized = output_dir.path().join("Localized.swift");
    fs::write(
        &localized,
        make_localized_swift(&["chat.title", "agent.name"]),
    )
    .unwrap();
    write_source(
        &src,
        "View.swift",
        r#"let a = String(localized: "chat.title")"#,
    );

    let result = validate(src.path().to_str().unwrap(), localized.to_str().unwrap()).unwrap();
    assert!(result);
}

#[test]
fn fails_on_unknown_key() {
    let src = TempDir::new().unwrap();
    let output_dir = TempDir::new().unwrap();

    let localized = output_dir.path().join("Localized.swift");
    fs::write(&localized, make_localized_swift(&["chat.title"])).unwrap();
    write_source(
        &src,
        "View.swift",
        r#"let a = String(localized: "chat.unknown")"#,
    );

    let result = validate(src.path().to_str().unwrap(), localized.to_str().unwrap()).unwrap();
    assert!(!result);
}

#[test]
fn skips_lines_containing_localized_get() {
    let src = TempDir::new().unwrap();
    let output_dir = TempDir::new().unwrap();

    let localized = output_dir.path().join("Localized.swift");
    fs::write(&localized, make_localized_swift(&[])).unwrap();
    // This line contains Localized.get( so it should be skipped entirely
    write_source(
        &src,
        "Localized.swift",
        r#"static var x: String { Localized.get("any.key") }"#,
    );

    let result = validate(src.path().to_str().unwrap(), localized.to_str().unwrap()).unwrap();
    assert!(result);
}

#[test]
fn skips_files_in_tests_directory() {
    let src = TempDir::new().unwrap();
    let output_dir = TempDir::new().unwrap();

    let localized = output_dir.path().join("Localized.swift");
    fs::write(&localized, make_localized_swift(&[])).unwrap();

    // File inside a Tests/ subdirectory should be ignored
    let tests_dir = src.path().join("Tests");
    fs::create_dir(&tests_dir).unwrap();
    fs::write(
        tests_dir.join("SomeTest.swift"),
        r#"String(localized: "nonexistent.key")"#,
    )
    .unwrap();

    let result = validate(src.path().to_str().unwrap(), localized.to_str().unwrap()).unwrap();
    assert!(result);
}

#[test]
fn reports_correct_line_number() {
    let src = TempDir::new().unwrap();
    let output_dir = TempDir::new().unwrap();

    let localized = output_dir.path().join("Localized.swift");
    fs::write(&localized, make_localized_swift(&["chat.title"])).unwrap();
    write_source(
        &src,
        "View.swift",
        "let a = 1\nlet b = 2\nlet c = String(localized: \"chat.bad\")\n",
    );

    // Capture stderr to verify line number — we just check it returns false
    // (line number verification relies on the printed output, tested via CLI)
    let result = validate(src.path().to_str().unwrap(), localized.to_str().unwrap()).unwrap();
    assert!(!result);
}

#[test]
fn ignores_non_swift_files() {
    let src = TempDir::new().unwrap();
    let output_dir = TempDir::new().unwrap();

    let localized = output_dir.path().join("Localized.swift");
    fs::write(&localized, make_localized_swift(&[])).unwrap();
    write_source(&src, "README.md", r#"String(localized: "nonexistent.key")"#);

    let result = validate(src.path().to_str().unwrap(), localized.to_str().unwrap()).unwrap();
    assert!(result);
}
