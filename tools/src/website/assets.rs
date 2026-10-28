//! Generate committed website branding assets from design tokens and local brand fonts.
use anyhow::{Context, Result, ensure};
use resvg::{tiny_skia, usvg};
use serde::Deserialize;
use std::{fs, path::Path};

#[derive(Deserialize)]
struct SocialCopy {
    en: CardCopy,
    da: CardCopy,
}

#[derive(Deserialize)]
struct CardCopy {
    tagline: [String; 2],
}

/// Render favicon, bookmark icon and localized social cards without system-font fallbacks.
pub(super) fn generate(root: &Path) -> Result<()> {
    let tokens = crate::design::tokens::load_tokens(&root.to_string_lossy())?;
    let color = |path: &str| -> Result<String> {
        let alias = format!("{{{path}}}");
        Ok(crate::design::tokens::resolve_alias(&tokens, &alias, "light", 0)?.to_string())
    };
    let background = color("color.surface.standard.base")?;
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
    let mut options = usvg::Options::default();
    options
        .fontdb_mut()
        .load_fonts_dir(root.join("design/assets/fonts"));
    let family = |role: &str, weight: &str| -> Result<String> {
        let name = tokens["fontFamily"][role][weight]
            .as_str()
            .context("font token")?;
        let face = options
            .fontdb
            .faces()
            .find(|face| face.post_script_name == name)
            .with_context(|| {
                format!(
                    "Install brand font {name} in design/assets/fonts to regenerate website assets"
                )
            })?;
        Ok(face.families.first().context("font family")?.0.clone())
    };
    let display = xml(&family("display", "bold")?);
    let serif = xml(&family("ui", "light")?);
    let copy: SocialCopy = serde_json::from_slice(&fs::read(
        root.join("src/eigin_website/src/lib/content/social.json"),
    )?)?;
    let out = root.join("src/eigin_website/static");
    fs::create_dir_all(out.join("social"))?;
    fs::write(out.join("favicon.svg"), &icon)?;
    render(&icon, &options, 32, 32, &out.join("favicon-32.png"))?;
    render(&icon, &options, 180, 180, &out.join("apple-touch-icon.png"))?;
    for (locale, card) in [("en", copy.en), ("da", copy.da)] {
        let first = xml(&card.tagline[0]);
        let second = xml(&card.tagline[1]);
        let logo = place_mark(&mark, 64, 54, 104);
        let svg = format!(
            r#"<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630">
<rect width="1200" height="630" fill="{background}"/>
<rect x="0" y="606" width="1200" height="24" fill="{brand}"/>
{logo}
<text x="184" y="133" font-family="{display}" font-size="64" font-weight="700" fill="{ink}">EIGIN</text>
<g font-family="{serif}" font-size="72" font-weight="300" fill="{ink}">
<text x="80" y="322">{first}</text>
<text x="80" y="408">{second}</text>
</g>
<text x="80" y="548" font-family="{display}" font-size="28" font-weight="700" fill="{ink}">eigin.ai</text>
</svg>"#
        );
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

fn xml(text: &str) -> String {
    text.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
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
