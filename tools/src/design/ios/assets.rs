use anyhow::{Context, Result};
use image::imageops;
use std::fs;

const CONTENTS_JSON: &str = r#"{
  "images": [
    {
      "filename": "AppIcon.png",
      "idiom": "universal",
      "platform": "ios",
      "size": "1024x1024"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  }
}
"#;

pub fn generate(repo_root: &str) -> Result<()> {
    let base_path = format!("{repo_root}/design/assets/icon/eigin_icon_light.png");
    let overlay_path = format!("{repo_root}/design/assets/icon/dev_overlay.png");
    let prod_dir =
        format!("{repo_root}/src/eigin_ios/Resources/Assets.xcassets/AppIcon.appiconset");
    let dev_dir =
        format!("{repo_root}/src/eigin_ios/Resources/Assets.xcassets/AppIconDev.appiconset");

    // Production — straight copy
    fs::copy(&base_path, format!("{prod_dir}/AppIcon.png"))
        .with_context(|| format!("copying base icon to {prod_dir}"))?;
    fs::write(format!("{prod_dir}/Contents.json"), CONTENTS_JSON)
        .with_context(|| format!("writing Contents.json to {prod_dir}"))?;

    // Dev — composite overlay centred on base
    let mut base = image::open(&base_path)
        .context("opening base icon")?
        .into_rgba8();
    let overlay = image::open(&overlay_path)
        .context("opening dev overlay")?
        .into_rgba8();
    let (bw, bh) = base.dimensions();
    let (ow, oh) = overlay.dimensions();
    let x = ((bw - ow) / 2) as i64;
    let y = ((bh - oh) / 2) as i64;
    imageops::overlay(&mut base, &overlay, x, y);
    base.save(format!("{dev_dir}/AppIcon.png"))
        .context("saving dev icon")?;
    fs::write(format!("{dev_dir}/Contents.json"), CONTENTS_JSON)
        .with_context(|| format!("writing Contents.json to {dev_dir}"))?;

    Ok(())
}
