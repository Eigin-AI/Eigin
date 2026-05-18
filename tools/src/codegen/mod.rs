pub mod ios;

use anyhow::{Context, Result};
use minijinja::{Environment, Value};
use std::fs;

pub fn render(env: &Environment, name: &str, ctx: Value) -> Result<String> {
    let template = env
        .get_template(name)
        .with_context(|| format!("template '{name}' not found"))?;
    template
        .render(ctx)
        .with_context(|| format!("rendering template '{name}'"))
}

pub fn write_file(output_dir: &str, filename: &str, content: &str) -> Result<()> {
    fs::create_dir_all(output_dir).with_context(|| format!("creating {output_dir}"))?;
    let path = format!("{output_dir}/{filename}");
    fs::write(&path, content).with_context(|| format!("writing {path}"))
}
