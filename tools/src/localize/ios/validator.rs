use anyhow::{Context, Result};
use regex::Regex;
use std::collections::HashSet;
use std::fs;
use walkdir::WalkDir;

pub fn validate(sources_dir: &str, localized_swift: &str) -> Result<bool> {
    let generated = fs::read_to_string(localized_swift)
        .with_context(|| format!("reading {localized_swift}"))?;
    let valid_keys = extract_keys(&generated);

    let key_pattern = Regex::new(r#"String\(localized:\s*"([^"]+)"#).unwrap();
    let get_pattern = Regex::new(r"Localized\.get\(").unwrap();

    let mut errors: Vec<(String, usize, String)> = Vec::new();

    for entry in WalkDir::new(sources_dir).into_iter().filter_map(|e| e.ok()) {
        let path = entry.path();
        let path_str = path.to_string_lossy();

        if path_str.contains("/.build/")
            || path_str.contains("/Pods/")
            || path_str.contains("/DerivedData/")
            || path_str.contains("/Tests/")
        {
            continue;
        }

        if path.extension().and_then(|e| e.to_str()) != Some("swift") {
            continue;
        }

        if path_str.contains("#Preview") {
            continue;
        }

        let content =
            fs::read_to_string(path).with_context(|| format!("reading {}", path.display()))?;

        for (line_idx, line) in content.lines().enumerate() {
            if get_pattern.is_match(line) {
                continue;
            }
            for cap in key_pattern.captures_iter(line) {
                let key = cap[1].to_string();
                if !valid_keys.contains(&key) {
                    errors.push((path.to_string_lossy().to_string(), line_idx + 1, key));
                }
            }
        }
    }

    if errors.is_empty() {
        println!("Validation passed. {} keys checked.", valid_keys.len());
        Ok(true)
    } else {
        eprintln!("Localization validation failed:");
        for (path, line, key) in &errors {
            eprintln!("{path}:{line}: unknown localization key '{key}'");
        }
        Ok(false)
    }
}

fn extract_keys(content: &str) -> HashSet<String> {
    let pattern = Regex::new(r#"Localized\.get\("([^"]+)"#).unwrap();
    pattern
        .captures_iter(content)
        .map(|cap| cap[1].to_string())
        .collect()
}
