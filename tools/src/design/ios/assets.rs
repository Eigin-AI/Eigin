use anyhow::{Context, Result};
use image::imageops;
use regex::Regex;
use serde_json::Value;
use std::fs;

use crate::design::tokens::resolve_alias;

const ICON_SIZE: u32 = 1024;
const LOGO_FRACTION: f32 = 0.70;

// Complication glyph — watchOS renders complications in accented mode on
// many faces, which flattens opaque artwork to a single face-colored tint.
// Only alpha survives, so the asset is the bare mark on transparency with
// template intent. watchOS also refuses images above 120x120 points; 44
// points with 1x/2x/3x renditions stays well under. The glyph fills this
// fraction of its canvas — the rest is margin, so the circular accessory
// never crops it.
const COMPLICATION_MARK_POINTS: u32 = 44;
const COMPLICATION_MARK_FILL: f32 = 0.7;

const COMPLICATION_CONTENTS_JSON: &str = r#"{
  "images" : [
    {
      "filename" : "complication_mark.png",
      "idiom" : "universal",
      "scale" : "1x"
    },
    {
      "filename" : "complication_mark@2x.png",
      "idiom" : "universal",
      "scale" : "2x"
    },
    {
      "filename" : "complication_mark@3x.png",
      "idiom" : "universal",
      "scale" : "3x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "properties" : {
    "template-rendering-intent" : "template"
  }
}
"#;

// Tinted icon: pure black bg + white logo (OS applies its own colour tint).
// These are absolute values not represented in the token system.
const TINTED_BG: [u8; 3] = [0x00, 0x00, 0x00];
const TINTED_ICON: &str = "#FFFFFF";

const PROD_CONTENTS_JSON: &str = r#"{
  "images" : [
    {
      "filename" : "AppIcon.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "filename" : "AppIconDark.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "tinted"
        }
      ],
      "filename" : "AppIconTinted.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "filename" : "AppIcon.png",
      "idiom" : "universal",
      "platform" : "watchos",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"#;

const DEV_CONTENTS_JSON: &str = r#"{
  "images" : [
    {
      "filename" : "AppIcon.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "filename" : "AppIcon.png",
      "idiom" : "universal",
      "platform" : "watchos",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"#;

pub fn generate(repo_root: &str, tokens: &Value) -> Result<()> {
    let light_bg = token_rgb(tokens, "palette.brand.primary", "light")?;
    let light_icon = token_hex(tokens, "color.icon.impact.base", "light")?;
    let dark_bg = token_rgb(tokens, "color.surface.standard.base", "dark")?;
    let dark_icon = token_hex(tokens, "palette.brand.primary", "light")?;

    let logo_path = format!("{repo_root}/design/assets/app_icon/logo.svg");
    let overlay_path = format!("{repo_root}/design/assets/app_icon/dev_overlay.png");
    let prod_dir =
        format!("{repo_root}/src/eigin_ios/Resources/Assets.xcassets/AppIcon.appiconset");
    let dev_dir =
        format!("{repo_root}/src/eigin_ios/Resources/Assets.xcassets/AppIconDev.appiconset");

    let logo_svg =
        fs::read_to_string(&logo_path).with_context(|| format!("reading {logo_path}"))?;
    let logo_size = (ICON_SIZE as f32 * LOGO_FRACTION) as u32;

    let light = make_icon(&logo_svg, light_bg, &light_icon, logo_size)?;
    let dark = make_icon(&logo_svg, dark_bg, &dark_icon, logo_size)?;
    let tinted = make_icon(&logo_svg, TINTED_BG, TINTED_ICON, logo_size)?;

    save_rgb(&light, &format!("{prod_dir}/AppIcon.png")).context("saving light icon")?;
    save_rgb(&dark, &format!("{prod_dir}/AppIconDark.png")).context("saving dark icon")?;
    save_rgb(&tinted, &format!("{prod_dir}/AppIconTinted.png")).context("saving tinted icon")?;
    fs::write(format!("{prod_dir}/Contents.json"), PROD_CONTENTS_JSON)
        .with_context(|| format!("writing Contents.json to {prod_dir}"))?;

    // Dev — light icon with dev overlay composited on top
    let dev = {
        let mut dev = light.clone();
        let overlay = image::open(&overlay_path)
            .context("opening dev overlay")?
            .into_rgba8();
        let (bw, bh) = dev.dimensions();
        let (ow, oh) = overlay.dimensions();
        let x = ((bw - ow) / 2) as i64;
        let y = ((bh - oh) / 2) as i64;
        imageops::overlay(&mut dev, &overlay, x, y);
        dev
    };
    save_rgb(&dev, &format!("{dev_dir}/AppIcon.png")).context("saving dev icon")?;
    fs::write(format!("{dev_dir}/Contents.json"), DEV_CONTENTS_JSON)
        .with_context(|| format!("writing Contents.json to {dev_dir}"))?;

    // Complication mark — the watch widget targets cannot see the main app
    // catalog, so they get a dedicated alpha-only glyph at widget scale.
    let complication_dir = format!(
        "{repo_root}/src/eigin_ios/WatchWidgets/ComplicationAssets.xcassets/complication_mark.imageset"
    );
    fs::create_dir_all(&complication_dir).context("creating complication markset")?;
    let colored = colorize_svg(&logo_svg, "#FFFFFF");
    for (scale, filename) in [
        (1u32, "complication_mark.png"),
        (2u32, "complication_mark@2x.png"),
        (3u32, "complication_mark@3x.png"),
    ] {
        let canvas = COMPLICATION_MARK_POINTS * scale;
        let glyph = render_svg(&colored, (canvas as f32 * COMPLICATION_MARK_FILL) as u32)?;
        let mut rendition = image::RgbaImage::new(canvas, canvas);
        let x = ((canvas - glyph.width()) / 2) as i64;
        let y = ((canvas - glyph.height()) / 2) as i64;
        imageops::overlay(&mut rendition, &glyph, x, y);
        save_rgb(&rendition, &format!("{complication_dir}/{filename}"))
            .context("saving complication mark")?;
    }
    fs::write(
        format!("{complication_dir}/Contents.json"),
        COMPLICATION_CONTENTS_JSON,
    )
    .with_context(|| format!("writing Contents.json to {complication_dir}"))?;

    Ok(())
}

fn save_rgb(img: &image::RgbaImage, path: &str) -> Result<()> {
    // Keep RGBA — the complication glyph depends on its alpha channel.
    image::DynamicImage::ImageRgba8(img.clone())
        .save(path)
        .with_context(|| format!("saving {path}"))
}

fn make_icon(
    logo_svg: &str,
    bg: [u8; 3],
    icon_color: &str,
    logo_size: u32,
) -> Result<image::RgbaImage> {
    let mut canvas = image::RgbaImage::from_pixel(
        ICON_SIZE,
        ICON_SIZE,
        image::Rgba([bg[0], bg[1], bg[2], 255]),
    );

    let colored = colorize_svg(logo_svg, icon_color);
    let logo = render_svg(&colored, logo_size)?;

    let x = ((ICON_SIZE - logo.width()) / 2) as i64;
    let y = ((ICON_SIZE - logo.height()) / 2) as i64;
    imageops::overlay(&mut canvas, &logo, x, y);

    Ok(canvas)
}

fn colorize_svg(svg: &str, color: &str) -> String {
    let re = Regex::new(r##"fill="#[0-9A-Fa-f]{3,8}""##).unwrap();
    re.replace_all(svg, format!("fill=\"{color}\"").as_str())
        .into_owned()
}

fn render_svg(svg_data: &str, max_size: u32) -> Result<image::RgbaImage> {
    use resvg::{tiny_skia, usvg};

    let options = usvg::Options::default();
    let tree = usvg::Tree::from_str(svg_data, &options).context("parsing SVG")?;

    let svg_w = tree.size().width();
    let svg_h = tree.size().height();
    let scale = max_size as f32 / svg_w.max(svg_h);
    let w = (svg_w * scale) as u32;
    let h = (svg_h * scale) as u32;

    let mut pixmap = tiny_skia::Pixmap::new(w, h)
        .ok_or_else(|| anyhow::anyhow!("failed to create {w}×{h} pixmap"))?;
    resvg::render(
        &tree,
        tiny_skia::Transform::from_scale(scale, scale),
        &mut pixmap.as_mut(),
    );

    image::RgbaImage::from_raw(w, h, pixmap.take()).context("converting pixmap to RgbaImage")
}

/// Resolves a token path (e.g. `"palette.brand.primary"`) to a hex string for the given mode.
fn token_hex(tokens: &Value, path: &str, mode: &str) -> Result<String> {
    let alias = format!("{{{path}}}");
    let hex = resolve_alias(tokens, &alias, mode, 0)
        .with_context(|| format!("resolving '{path}' in {mode} mode"))?;
    Ok(hex.to_string())
}

/// Resolves a token path to a `[u8; 3]` RGB triple.
fn token_rgb(tokens: &Value, path: &str, mode: &str) -> Result<[u8; 3]> {
    let hex = token_hex(tokens, path, mode)?;
    parse_hex_rgb(&hex).with_context(|| format!("parsing colour '{hex}' for token '{path}'"))
}

fn parse_hex_rgb(hex: &str) -> Option<[u8; 3]> {
    let h = hex.strip_prefix('#')?;
    if h.len() != 6 {
        return None;
    }
    Some([
        u8::from_str_radix(&h[0..2], 16).ok()?,
        u8::from_str_radix(&h[2..4], 16).ok()?,
        u8::from_str_radix(&h[4..6], 16).ok()?,
    ])
}
