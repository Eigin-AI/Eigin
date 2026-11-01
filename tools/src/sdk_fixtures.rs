//! Test-only error propagation through the real SDK binding generators.

use anyhow::{Result, bail};
use std::fs;
use std::process::Command;

use crate::sdk::run;

/// Select the host binding fixture to prepare and check.
#[derive(clap::Args)]
pub struct Args {
    #[arg(value_enum)]
    target: Target,
}

#[derive(Clone, Copy, clap::ValueEnum)]
enum Target {
    Web,
    Apple,
}

/// Check only the selected host's binding fixture.
pub fn run_check(args: Args) -> Result<()> {
    let root = crate::config::repo_root()?;
    let sdk = format!("{root}/src/eigin_sdk");
    match args.target {
        Target::Web => web(&root, &sdk),
        Target::Apple => {
            if !cfg!(target_os = "macos") {
                bail!("Swift binding fixtures require macOS and Xcode");
            }
            swift(&sdk)
        }
    }
}

fn web(root: &str, sdk: &str) -> Result<()> {
    crate::sdk::ensure_web_dependencies(root)?;
    run(Command::new(format!("{root}/node_modules/.bin/ubrn"))
        .args([
            "build",
            "wasm2",
            "--config",
            "ubrn.fixtures.config.yaml",
            "--release",
        ])
        .current_dir(format!("{sdk}/web")))
}

fn swift(sdk: &str) -> Result<()> {
    let target = format!("{sdk}/target/binding-tests");
    let generated = format!("{target}/swift");
    if std::path::Path::new(&generated).exists() {
        fs::remove_dir_all(&generated)?;
    }
    fs::create_dir_all(&generated)?;
    run(Command::new("cargo")
        .args([
            "build",
            "--locked",
            "-p",
            "eigin_sdk",
            "--features",
            "binding-tests",
            "--target-dir",
            &target,
        ])
        .current_dir(sdk))?;
    run(Command::new("cargo")
        .args([
            "run",
            "--locked",
            "-p",
            "eigin-sdk-bindgen",
            "--",
            "generate",
            "--library",
            &format!("{target}/debug/libeigin_sdk.dylib"),
            "--language",
            "swift",
            "--out-dir",
            &generated,
        ])
        .current_dir(sdk))?;
    fs::copy(
        format!("{generated}/eigin_sdkFFI.modulemap"),
        format!("{generated}/module.modulemap"),
    )?;
    let executable = format!("{target}/check-swift-errors");
    run(Command::new("swiftc").args([
        "-parse-as-library",
        "-I",
        &generated,
        "-L",
        &format!("{target}/debug"),
        "-leigin_sdk",
        "-Xlinker",
        "-rpath",
        "-Xlinker",
        &format!("{target}/debug"),
        &format!("{generated}/eigin_sdk.swift"),
        &format!("{sdk}/tests/BindingErrors.swift"),
        "-o",
        &executable,
    ]))?;
    run(&mut Command::new(executable))
}
