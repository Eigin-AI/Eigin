mod assets;
mod fonts;
mod style;

/// Generate all iOS design artifacts: Swift design tokens, custom fonts, and app icon assets.
pub fn generate(repo_root: &str) -> anyhow::Result<()> {
    let tokens = style::load_tokens(repo_root)?;
    let installed = fonts::install(repo_root, &tokens)?;
    style::generate(repo_root, &tokens, installed.as_ref())?;
    assets::generate(repo_root)
}
