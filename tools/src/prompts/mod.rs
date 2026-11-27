pub mod catalog;
pub mod ios;
mod parser;
mod swift;

/// Generate app-owned flow and icebreaker registries.
/// Called by `eigin-tools generate` as part of the standard codegen pipeline.
pub fn generate_all(repo_root: &str) -> anyhow::Result<()> {
    ios::generate(repo_root)
}
