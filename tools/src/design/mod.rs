//! Design codegen: `design/` sources in, platform code out.

pub mod ios;
pub mod tokens;
pub mod web;

/// Generate all design artifacts for all platforms.
/// Called by `eigin-tools generate` as part of the standard codegen pipeline.
pub fn generate_all(repo_root: &str) -> anyhow::Result<()> {
    let tokens = tokens::load_tokens(repo_root)?;
    let installed = ios::fonts::install(repo_root, &tokens)?;
    ios::style::generate(repo_root, &tokens, installed.as_ref())?;
    ios::assets::generate(repo_root, &tokens)?;
    ios::icons::generate(repo_root)?;
    web::generate(repo_root, &tokens, installed.as_ref())
}
