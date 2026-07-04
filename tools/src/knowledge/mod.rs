pub mod ios;

/// Generate the bundled-knowledge registry from the `design/knowledge` firm
/// workspace. Called by `eigin-tools generate` as part of the standard codegen
/// pipeline.
pub fn generate_all(repo_root: &str) -> anyhow::Result<()> {
    ios::generate(repo_root)
}
