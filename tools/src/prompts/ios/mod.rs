pub mod flows;
pub mod icebreakers;

use super::swift as generator;
use anyhow::{Context, Result};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

const SOURCE_REL: &str = "design/prompts";
const FLOW_REGISTRY_OUTPUT_REL: &str =
    "src/eigin_ios/Sources/Core/Content/Generated/FlowRegistry.swift";
const ICEBREAKER_REGISTRY_OUTPUT_REL: &str =
    "src/eigin_ios/Sources/Core/Content/Generated/IcebreakerRegistry.swift";

/// Generate app-owned flow and icebreaker registries referencing the SDK prompt API.
pub fn generate(repo_root: &str) -> Result<()> {
    let source_dir = PathBuf::from(repo_root).join(SOURCE_REL);
    let flow_output_path = PathBuf::from(repo_root).join(FLOW_REGISTRY_OUTPUT_REL);
    let icebreaker_output_path = PathBuf::from(repo_root).join(ICEBREAKER_REGISTRY_OUTPUT_REL);

    let catalog = super::catalog::load(Path::new(repo_root))?;
    let templates = catalog.templates;
    let params = generator::resolve_all_params(&templates)?;

    let mut resolved_flows = Vec::new();
    flows::collect(
        &source_dir,
        &source_dir,
        &templates,
        &params,
        &mut resolved_flows,
    )?;
    let flow_swift = flows::emit(&resolved_flows).context("generating FlowRegistry.swift")?;
    write_swift(&flow_output_path, &flow_swift)?;

    let groups = icebreakers::collect(&source_dir)?;
    let icebreaker_swift =
        icebreakers::emit(&groups).context("generating IcebreakerRegistry.swift")?;
    write_swift(&icebreaker_output_path, &icebreaker_swift)?;

    Ok(())
}

fn write_swift(output_path: &Path, swift: &str) -> Result<()> {
    let parent = output_path.parent().unwrap();
    fs::create_dir_all(parent).with_context(|| format!("creating {}", parent.display()))?;
    fs::write(output_path, swift).with_context(|| format!("writing {}", output_path.display()))?;

    let status = Command::new("swiftformat")
        .arg(output_path)
        .status()
        .context("running swiftformat")?;
    if !status.success() {
        anyhow::bail!("swiftformat failed on {}", output_path.display());
    }

    println!("Generated {}", output_path.display());
    Ok(())
}
