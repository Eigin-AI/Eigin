//! Generate committed website branding assets from design tokens and brand illustrations.
use anyhow::{Context, Result, ensure};
use resvg::{tiny_skia, usvg};
use std::{fs, path::Path};

/// Render favicon, bookmark icon and social cards from shared brand artwork.
pub(super) fn generate(root: &Path) -> Result<()> {
    let tokens = crate::design::tokens::load_tokens(&root.to_string_lossy())?;
    let color = |path: &str| -> Result<String> {
        let alias = format!("{{{path}}}");
        Ok(crate::design::tokens::resolve_alias(&tokens, &alias, "light", 0)?.to_string())
    };
    let ink = color("color.text.standard.base")?;
    let brand = color("color.surface.impact.base")?;
    let mark = fs::read_to_string(root.join("design/assets/icons/brand/avatar.svg"))?;
    let mark = regex::Regex::new(r##"fill="#[0-9A-Fa-f]{3,8}""##)?
        .replace_all(&mark, format!("fill=\"{ink}\""))
        .into_owned();
    let icon = format!(
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"180\" height=\"180\" viewBox=\"0 0 180 180\"><rect width=\"180\" height=\"180\" fill=\"{brand}\"/>{}</svg>",
        place_mark(&mark, 7, 7, 166)
    );
    let options = usvg::Options::default();
    let bird = fs::read_to_string(root.join("design/assets/icons/illustration/hero-bird.svg"))?
        .replace("currentColor", &ink)
        .replace(
            "<svg ",
            "<svg x=\"335\" y=\"67\" width=\"530\" height=\"496\" ",
        );
    // Keep the bird inside the central square for compact link-preview crops.
    let svg = format!(
        r#"<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630">
<rect width="1200" height="630" fill="{brand}"/>
{bird}
</svg>"#
    );
    let out = root.join("src/eigin_website/static");
    fs::create_dir_all(out.join("social"))?;
    fs::write(out.join("favicon.svg"), &icon)?;
    render(&icon, &options, 32, 32, &out.join("favicon-32.png"))?;
    render(&icon, &options, 180, 180, &out.join("apple-touch-icon.png"))?;
    for locale in ["en", "da"] {
        render(
            &svg,
            &options,
            1200,
            630,
            &out.join(format!("social/{locale}.png")),
        )?;
    }
    println!("Generated website branding assets in {}", out.display());
    Ok(())
}

fn place_mark(mark: &str, x: u32, y: u32, size: u32) -> String {
    mark.replace("<svg ", &format!("<svg x=\"{x}\" y=\"{y}\" "))
        .replace("width=\"167\"", &format!("width=\"{size}\""))
        .replace("height=\"166\"", &format!("height=\"{size}\""))
}

fn render(svg: &str, options: &usvg::Options, width: u32, height: u32, path: &Path) -> Result<()> {
    let tree = usvg::Tree::from_str(svg, options).context("parsing website artwork")?;
    let mut pixels = tiny_skia::Pixmap::new(width, height).context("allocating website artwork")?;
    ensure!(tree.size().width() > 0.0, "Empty artwork");
    resvg::render(
        &tree,
        tiny_skia::Transform::from_scale(
            width as f32 / tree.size().width(),
            height as f32 / tree.size().height(),
        ),
        &mut pixels.as_mut(),
    );
    pixels
        .save_png(path)
        .with_context(|| format!("writing {}", path.display()))?;
    Ok(())
}
