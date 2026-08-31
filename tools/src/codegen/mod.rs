pub mod ios;

use anyhow::{Context, Result};
use minijinja::{Environment, Value};
use std::fs;
use std::path::Path;

pub fn render(env: &Environment, name: &str, ctx: Value) -> Result<String> {
    let template = env
        .get_template(name)
        .with_context(|| format!("template '{name}' not found"))?;
    template
        .render(ctx)
        .with_context(|| format!("rendering template '{name}'"))
}

/// Writes generated content, always newline-terminated — minijinja trims the
/// template's trailing newline, and swiftformat lints for it.
pub fn write_file(output_dir: &str, filename: &str, content: &str) -> Result<()> {
    fs::create_dir_all(output_dir).with_context(|| format!("creating {output_dir}"))?;
    let path = format!("{output_dir}/{filename}");
    let content = if content.ends_with('\n') {
        content.to_string()
    } else {
        format!("{content}\n")
    };
    fs::write(&path, content).with_context(|| format!("writing {path}"))
}

/// Deletes generated Swift in `legacy_dir` that `current_dir` now owns.
///
/// Generated Swift is gitignored, so a checkout that predates a move keeps the
/// old copies on disk and Xcode fails on the duplicate filename. Only `.swift`
/// is swept — the directories share a `.gitignore` that both must keep.
pub fn remove_stale_duplicates(current_dir: &str, legacy_dir: &str) -> Result<()> {
    let legacy = Path::new(legacy_dir);
    if !legacy.is_dir() {
        return Ok(());
    }
    for entry in fs::read_dir(current_dir).with_context(|| format!("reading {current_dir}"))? {
        let path = entry
            .with_context(|| format!("reading {current_dir}"))?
            .path();
        if path.extension().and_then(|e| e.to_str()) != Some("swift") {
            continue;
        }
        let Some(name) = path.file_name() else {
            continue;
        };
        let stale = legacy.join(name);
        if stale.is_file() {
            fs::remove_file(&stale).with_context(|| format!("removing {}", stale.display()))?;
        }
    }
    Ok(())
}
