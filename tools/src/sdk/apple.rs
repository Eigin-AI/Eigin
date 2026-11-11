//! Apple dynamic framework generation.

use anyhow::{Context, Result, bail};
use std::{fs, path::Path, process::Command};

use super::{copy_if_changed, run};

fn cargo(root: &str) -> Command {
    let mut command = Command::new("cargo");
    command.current_dir(format!("{root}/src/eigin_sdk"));
    // Match the package/framework minimums for Rust and native TLS dependencies.
    command.env("IPHONEOS_DEPLOYMENT_TARGET", "26.0");
    command.env("MACOSX_DEPLOYMENT_TARGET", "15.0");
    command
}

pub(super) fn generate(root: &str) -> Result<()> {
    if !cfg!(target_os = "macos") {
        bail!(
            "Apple SDK artifacts require macOS and Xcode; use `just generate sdk web` for portable work"
        );
    }
    let sdk = format!("{root}/src/eigin_sdk");
    let package = format!("{sdk}/apple/EiginSDK");
    let generated = format!("{package}/Sources/EiginSDKBindings");
    run(cargo(root).args(["build", "-p", "eigin_sdk", "--release", "--locked"]))?;
    // Generate to a temporary directory so removed API files cannot survive regeneration.
    let staging = format!("{sdk}/target/swift-bindings");
    if Path::new(&staging).exists() {
        fs::remove_dir_all(&staging)?;
    }
    run(cargo(root).args([
        "run",
        "--locked",
        "-p",
        "eigin-sdk-bindgen",
        "--",
        "generate",
        "--library",
        "target/release/libeigin_sdk.dylib",
        "--language",
        "swift",
        "--out-dir",
        &staging,
    ]))?;
    fs::create_dir_all(&generated)?;
    for entry in fs::read_dir(&generated)? {
        let entry = entry?;
        if entry.file_name() != "eigin_sdk.swift" {
            fs::remove_file(entry.path())?;
        }
    }
    copy_if_changed(
        Path::new(&format!("{staging}/eigin_sdk.swift")),
        Path::new(&format!("{generated}/eigin_sdk.swift")),
    )?;
    let headers = format!("{sdk}/target/sdk-headers");
    fs::create_dir_all(&headers)?;
    fs::copy(
        format!("{staging}/eigin_sdkFFI.h"),
        format!("{headers}/eigin_sdkFFI.h"),
    )?;
    fs::copy(
        format!("{staging}/eigin_sdkFFI.modulemap"),
        format!("{headers}/module.modulemap"),
    )?;

    let groups: &[(&str, &[&str])] = &[
        ("ios", &["aarch64-apple-ios"]),
        ("simulator", &["aarch64-apple-ios-sim", "x86_64-apple-ios"]),
        ("macos", &["aarch64-apple-darwin", "x86_64-apple-darwin"]),
    ];
    let mut libraries = Vec::new();
    for (group, targets) in groups {
        let mut paths = Vec::new();
        for target in *targets {
            run(Command::new("rustup")
                .args(["target", "add", target])
                .current_dir(&sdk))?;
            run(cargo(root).args([
                "build",
                "--locked",
                "--release",
                "-p",
                "eigin_sdk",
                "--target",
                target,
            ]))?;
            paths.push(format!("{sdk}/target/{target}/release/libeigin_sdk.dylib"));
        }
        let output = format!("{sdk}/target/libeigin_sdk-{group}.dylib");
        run(Command::new("lipo")
            .arg("-create")
            .args(&paths)
            .args(["-output", &output]))?;
        // Dynamic linkage isolates the SDK runtime from Firm's existing Rust static library.
        let framework = format!("{sdk}/target/{group}/eigin_sdkFFI.framework");
        if Path::new(&framework).exists() {
            fs::remove_dir_all(&framework)?;
        }
        fs::create_dir_all(format!("{framework}/Headers"))?;
        fs::create_dir_all(format!("{framework}/Modules"))?;
        fs::copy(&output, format!("{framework}/eigin_sdkFFI"))?;
        run(Command::new("install_name_tool").args([
            "-id",
            "@rpath/eigin_sdkFFI.framework/eigin_sdkFFI",
            &format!("{framework}/eigin_sdkFFI"),
        ]))?;
        fs::copy(
            format!("{headers}/eigin_sdkFFI.h"),
            format!("{framework}/Headers/eigin_sdkFFI.h"),
        )?;
        fs::write(
            format!("{framework}/Modules/module.modulemap"),
            "framework module eigin_sdkFFI {\n  umbrella header \"eigin_sdkFFI.h\"\n  export *\n  module * { export * }\n}\n",
        )?;
        let (platform, minimum) = match *group {
            "ios" => ("iPhoneOS", "26.0"),
            "simulator" => ("iPhoneSimulator", "26.0"),
            _ => ("MacOSX", "15.0"),
        };
        fs::write(
            format!("{framework}/Info.plist"),
            format!(
                r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>eigin_sdkFFI</string>
<key>CFBundleIdentifier</key><string>ai.eigin.sdk.bindings</string>
<key>CFBundleName</key><string>eigin_sdkFFI</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleSupportedPlatforms</key><array><string>{platform}</string></array>
<key>MinimumOSVersion</key><string>{minimum}</string>
</dict></plist>
"#
            ),
        )?;
        // Editing the install name invalidates the linker signature on Apple Silicon.
        run(Command::new("codesign").args([
            "--force",
            "--sign",
            "-",
            &format!("{framework}/eigin_sdkFFI"),
        ]))?;
        libraries.push(framework);
    }
    let artifact = format!("{package}/Artifacts/EiginSDKBindings.xcframework");
    fs::create_dir_all(format!("{package}/Artifacts"))?;
    let mut command = Command::new("xcodebuild");
    command.arg("-create-xcframework");
    for library in &libraries {
        command.args(["-framework", library]);
    }
    let temporary = format!("{sdk}/target/EiginSDKBindings.xcframework");
    if Path::new(&temporary).exists() {
        fs::remove_dir_all(&temporary)?;
    }
    command.args(["-output", &temporary]);
    run(&mut command)?;
    // Xcode emits platform entries in nondeterministic order.
    let manifest = format!("{temporary}/Info.plist");
    let output = Command::new("plutil")
        .args(["-convert", "json", "-o", "-", &manifest])
        .output()?;
    if !output.status.success() {
        bail!("Cannot read XCFramework manifest");
    }
    let mut value: serde_json::Value = serde_json::from_slice(&output.stdout)?;
    let entries = value["AvailableLibraries"]
        .as_array_mut()
        .context("XCFramework libraries missing")?;
    entries.sort_by_key(|entry| {
        entry["LibraryIdentifier"]
            .as_str()
            .unwrap_or_default()
            .to_owned()
    });
    for entry in entries {
        if let Some(architectures) = entry["SupportedArchitectures"].as_array_mut() {
            architectures.sort_by_key(|arch| arch.as_str().unwrap_or_default().to_owned());
        }
    }
    fs::write(&manifest, serde_json::to_vec(&value)?)?;
    run(Command::new("plutil").args(["-convert", "xml1", &manifest]))?;
    // Leave an unchanged package artifact in place so SwiftPM can reuse its build.
    let equal = Command::new("diff")
        .args(["-qr", &artifact, &temporary])
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false);
    if equal {
        fs::remove_dir_all(temporary)?;
    } else {
        let previous = format!("{package}/Artifacts/EiginSDKBindings.previous.xcframework");
        if Path::new(&previous).exists() {
            fs::remove_dir_all(&previous)?;
        }
        let had_previous = Path::new(&artifact).exists();
        if had_previous {
            fs::rename(&artifact, &previous)?;
        }
        if let Err(error) = fs::rename(&temporary, &artifact) {
            if had_previous {
                fs::rename(&previous, &artifact)?;
            }
            return Err(error.into());
        }
        if had_previous {
            fs::remove_dir_all(previous)?;
        }
    }
    Ok(())
}
