mod assets;
mod fonts;
pub mod icons;
pub mod model;
pub mod style;
pub mod swift_mappings;

/// Generate all iOS design artifacts: Swift design tokens, custom fonts, app icons, and icon assets.
pub fn generate(repo_root: &str) -> anyhow::Result<()> {
    let tokens = style::load_tokens(repo_root)?;
    let installed = fonts::install(repo_root, &tokens)?;
    style::generate(repo_root, &tokens, installed.as_ref())?;
    assets::generate(repo_root, &tokens)?;
    icons::generate(repo_root)
}
