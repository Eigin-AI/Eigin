//! Design codegen: `design/` sources in, platform code out.

pub mod ios;
pub mod tokens;
pub mod web;

/// Generate all design artifacts for all platforms.
/// Called by `eigin-tools generate` as part of the standard codegen pipeline.
pub fn generate_all(repo_root: &str) -> anyhow::Result<()> {
    let tokens = tokens::load_tokens(repo_root)?;
    let installed = ios::fonts::install(repo_root, &tokens)?;
    generate_ios_assets(repo_root, &tokens, installed.as_ref())?;
    web::generate(repo_root, &tokens, installed.as_ref())
}

/// Generate design artifacts used by the iOS app.
pub fn generate_ios(repo_root: &str) -> anyhow::Result<()> {
    let tokens = tokens::load_tokens(repo_root)?;
    let installed = ios::fonts::install(repo_root, &tokens)?;
    generate_ios_assets(repo_root, &tokens, installed.as_ref())
}

fn generate_ios_assets(
    repo_root: &str,
    tokens: &serde_json::Value,
    installed: Option<&ios::fonts::InstalledFonts>,
) -> anyhow::Result<()> {
    ios::style::generate(repo_root, tokens, installed)?;
    ios::assets::generate(repo_root, tokens)?;
    ios::launch::generate(repo_root, tokens)?;
    ios::icons::generate(repo_root)
}
