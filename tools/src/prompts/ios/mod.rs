pub mod generator;
pub mod parser;

use anyhow::{Context, Result};
use std::fs;
use std::path::{MAIN_SEPARATOR, Path, PathBuf};
use std::process::Command;

const SOURCE_REL: &str = "design/prompts";
const OUTPUT_REL: &str = "src/eigin_ios/Sources/Core/Design/Generated/Prompt.swift";

/// Compile every `design/prompts/**/*.jinja` template into typed Swift accessors
/// at `Sources/Core/Design/Generated/Prompt.swift`, mirroring the folder tree into
/// nested enums. Called by `eigin-tools generate`.
pub fn generate(repo_root: &str) -> Result<()> {
    let source_dir = PathBuf::from(repo_root).join(SOURCE_REL);
    let output_path = PathBuf::from(repo_root).join(OUTPUT_REL);

    if !source_dir.exists() {
        if output_path.exists() {
            fs::remove_file(&output_path)
                .with_context(|| format!("removing {}", output_path.display()))?;
        }
        return Ok(());
    }

    let mut templates = generator::Templates::new();
    collect(&source_dir, &source_dir, &mut templates)?;

    let swift = generator::emit(&templates).context("generating Prompt.swift")?;

    let parent = output_path.parent().unwrap();
    fs::create_dir_all(parent).with_context(|| format!("creating {}", parent.display()))?;
    fs::write(&output_path, &swift)
        .with_context(|| format!("writing {}", output_path.display()))?;

    let status = Command::new("swiftformat")
        .arg(&output_path)
        .status()
        .context("running swiftformat")?;
    if !status.success() {
        anyhow::bail!("swiftformat failed on {}", output_path.display());
    }

    println!("Generated {}", output_path.display());
    Ok(())
}

fn collect(root: &Path, dir: &Path, templates: &mut generator::Templates) -> Result<()> {
    for entry in fs::read_dir(dir).with_context(|| format!("reading {}", dir.display()))? {
        let path = entry?.path();
        if path.is_dir() {
            collect(root, &path, templates)?;
        } else if path.extension().and_then(|s| s.to_str()) == Some("jinja") {
            let rel = path
                .strip_prefix(root)
                .unwrap()
                .to_str()
                .ok_or_else(|| anyhow::anyhow!("non-utf8 path {}", path.display()))?
                .replace(MAIN_SEPARATOR, "/");
            let source =
                fs::read_to_string(&path).with_context(|| format!("reading {}", path.display()))?;
            let segments = parser::parse(&source).with_context(|| format!("parsing {rel}"))?;
            templates.insert(rel, segments);
        }
    }
    Ok(())
}
