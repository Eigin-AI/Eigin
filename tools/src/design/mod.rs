pub mod ios;

/// Generate all design artifacts for all platforms.
/// Called by `eigin-tools generate` as part of the standard codegen pipeline.
pub fn generate_all(repo_root: &str) -> anyhow::Result<()> {
    ios::generate(repo_root)
}
