use super::generate;
use std::fs;
use std::path::Path;
use std::process::Command;

const OUTPUTS: &[&str] = &[
    "src/eigin_sdk/THIRD-PARTY-NOTICES.txt",
    "src/eigin_sdk/apple/EiginSDK/Sources/EiginSDK/Resources/THIRD-PARTY-NOTICES.txt",
    "src/eigin_sdk/web/THIRD-PARTY-NOTICES.txt",
    "src/eigin_web/public/SDK-NOTICES.txt",
];

fn write(root: &Path, path: &str, text: &str) {
    let path = root.join(path);
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    fs::write(path, text).unwrap();
}

fn package(root: &Path, path: &str, name: &str, dependencies: &str) {
    write(
        root,
        &format!("{path}/Cargo.toml"),
        &format!(
            "[package]\nname = {name:?}\nversion = \"1.0.0\"\nedition = \"2024\"\nlicense = \"MIT\"\n[workspace]\n{dependencies}"
        ),
    );
    write(root, &format!("{path}/src/lib.rs"), "");
    write(
        root,
        &format!("{path}/LICENSE"),
        &format!("License for {name}"),
    );
}

fn fixture() -> tempfile::TempDir {
    let directory = tempfile::tempdir().unwrap();
    let root = directory.path();
    write(root, "config/app.toml", "[version]\nsdk = \"0.4.2\"\n");
    write(root, "LICENSE", "SDK license text");
    for name in [
        "runtime",
        "transitive",
        "wasm-runtime",
        "dev-only",
        "build-only",
        "macro-only",
        "host-only",
    ] {
        let dependencies = match name {
            "runtime" => "[dependencies]\ntransitive = { path = \"../transitive\" }",
            "macro-only" => "[lib]\nproc-macro = true",
            _ => "",
        };
        package(root, &format!("deps/{name}"), name, dependencies);
    }
    package(
        root,
        "src/eigin_sdk",
        "eigin_sdk",
        r#"
[dependencies]
runtime = { path = "../../deps/runtime" }
macro-only = { path = "../../deps/macro-only" }
[target.'cfg(target_arch = "wasm32")'.dependencies]
wasm-runtime = { path = "../../deps/wasm-runtime" }
[dev-dependencies]
dev-only = { path = "../../deps/dev-only" }
[build-dependencies]
build-only = { path = "../../deps/build-only" }
"#,
    );
    package(
        root,
        "src/eigin_cli",
        "host",
        r#"
[dependencies]
eigin_sdk = { path = "../eigin_sdk" }
host-only = { path = "../../deps/host-only" }
"#,
    );
    write(
        root,
        "deps/runtime/COPYRIGHT",
        "Copyright runtime contributors",
    );
    write(
        root,
        "deps/runtime/NOTICE",
        "Additional runtime attribution",
    );
    for manifest in ["src/eigin_sdk/Cargo.toml", "src/eigin_cli/Cargo.toml"] {
        let output = Command::new("cargo")
            .args(["generate-lockfile", "--offline", "--manifest-path"])
            .arg(root.join(manifest))
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
    }
    write(root, "package-lock.json", &serde_json::json!({"packages": {
        "src/eigin_sdk/web": {"dependencies": {"browser-runtime": "1"}, "devDependencies": {"browser-tool": "1"}},
        "node_modules/browser-runtime": {"version": "1", "peerDependencies": {"browser-peer": "1"}},
        "node_modules/browser-peer": {"version": "1"},
        "node_modules/browser-tool": {"version": "1"}
    }}).to_string());
    for name in ["browser-runtime", "browser-peer", "browser-tool"] {
        write(
            root,
            &format!("node_modules/{name}/package.json"),
            &serde_json::json!({
                "name": name, "version": "1", "license": "MIT"
            })
            .to_string(),
        );
        write(
            root,
            &format!("node_modules/{name}/LICENSE"),
            &format!("License for {name}"),
        );
    }
    directory
}

#[test]
fn generates_runtime_notices_for_every_host() {
    let directory = fixture();
    let root = directory.path();
    generate(root.to_str().unwrap(), false).unwrap();
    let text = fs::read_to_string(root.join(OUTPUTS[0])).unwrap();
    for name in [
        "runtime",
        "transitive",
        "wasm-runtime",
        "browser-runtime",
        "browser-peer",
    ] {
        assert!(
            text.contains(&format!("License for {name}")),
            "missing {name}"
        );
    }
    for name in [
        "dev-only",
        "build-only",
        "macro-only",
        "host-only",
        "browser-tool",
    ] {
        assert!(!text.contains(name), "unexpected {name}");
    }
    assert!(text.contains("Copyright runtime contributors"));
    assert!(text.contains("Additional runtime attribution"));
    for path in OUTPUTS {
        assert_eq!(fs::read_to_string(root.join(path)).unwrap(), text);
    }
    generate(root.to_str().unwrap(), true).unwrap();
    generate(root.to_str().unwrap(), false).unwrap();
    assert_eq!(fs::read_to_string(root.join(OUTPUTS[0])).unwrap(), text);
}

#[test]
fn missing_runtime_license_prevents_output() {
    let directory = fixture();
    let root = directory.path();
    for path in [
        "deps/runtime/LICENSE",
        "node_modules/browser-runtime/LICENSE",
    ] {
        let license = fs::read(root.join(path)).unwrap();
        fs::remove_file(root.join(path)).unwrap();
        let error = generate(root.to_str().unwrap(), false).unwrap_err();
        assert!(error.to_string().contains("No license text"), "{error:#}");
        for output in OUTPUTS {
            assert!(!root.join(output).exists());
        }
        fs::write(root.join(path), license).unwrap();
    }
}

#[test]
fn check_rejects_stale_and_missing_copies_without_writing() {
    let directory = fixture();
    let root = directory.path();
    generate(root.to_str().unwrap(), false).unwrap();
    let original = fs::read(root.join(OUTPUTS[0])).unwrap();
    for path in OUTPUTS {
        fs::write(root.join(path), "stale").unwrap();
        assert!(
            generate(root.to_str().unwrap(), true)
                .unwrap_err()
                .to_string()
                .contains("Stale SDK notices")
        );
        for output in OUTPUTS {
            let expected: &[u8] = if output == path { b"stale" } else { &original };
            assert_eq!(fs::read(root.join(output)).unwrap(), expected);
        }
        fs::remove_file(root.join(path)).unwrap();
        assert!(generate(root.to_str().unwrap(), true).is_err());
        assert!(!root.join(path).exists());
        for output in OUTPUTS.iter().filter(|output| *output != path) {
            assert_eq!(fs::read(root.join(output)).unwrap(), original);
        }
        generate(root.to_str().unwrap(), false).unwrap();
        assert_eq!(fs::read(root.join(path)).unwrap(), original);
    }
}

#[test]
fn shares_identical_licenses_and_selects_mit_without_dropping_attribution() {
    let directory = fixture();
    let root = directory.path();
    let mit = "Copyright shared contributors\nMIT permission and disclaimer\n";
    for (name, expression) in [
        ("runtime", "MIT OR Apache-2.0"),
        ("transitive", "Apache-2.0 OR MIT"),
    ] {
        let manifest = root.join(format!("deps/{name}/Cargo.toml"));
        let text = fs::read_to_string(&manifest)
            .unwrap()
            .replace("license = \"MIT\"", &format!("license = {expression:?}"));
        fs::write(manifest, text).unwrap();
        fs::remove_file(root.join(format!("deps/{name}/LICENSE"))).unwrap();
        write(root, &format!("deps/{name}/LICENSE-MIT"), mit);
        write(
            root,
            &format!("deps/{name}/LICENSE-APACHE"),
            "Unselected Apache text",
        );
    }
    write(
        root,
        "deps/wasm-runtime/LICENSE",
        "Copyright different contributors\nMIT permission and disclaimer\n",
    );
    generate(root.to_str().unwrap(), false).unwrap();
    let text = fs::read_to_string(root.join(OUTPUTS[0])).unwrap();
    assert_eq!(text.matches(mit).count(), 1);
    assert_eq!(text.matches("Selected license: MIT").count(), 2);
    assert!(!text.contains("Unselected Apache text"));
    assert!(text.contains("Copyright different contributors"));
    assert!(text.contains("Copyright runtime contributors"));
    assert!(text.contains("Additional runtime attribution"));
    let references: Vec<_> = text
        .lines()
        .filter(|line| line.starts_with("LICENSE-MIT: see license text "))
        .collect();
    assert_eq!(references.len(), 2);
    assert_eq!(references[0], references[1]);
    let number = references[0]
        .strip_prefix("LICENSE-MIT: see license text ")
        .unwrap()
        .strip_suffix(" below.")
        .unwrap();
    assert!(text.contains(&format!("License text {number}\n\n{mit}")));
    generate(root.to_str().unwrap(), true).unwrap();

    fs::remove_file(root.join("deps/runtime/LICENSE-MIT")).unwrap();
    assert!(
        generate(root.to_str().unwrap(), false)
            .unwrap_err()
            .to_string()
            .contains("Missing MIT license text")
    );
    for path in OUTPUTS {
        assert_eq!(fs::read_to_string(root.join(path)).unwrap(), text);
    }
}

#[test]
fn retains_both_texts_when_both_licenses_are_required() {
    let directory = fixture();
    let root = directory.path();
    let manifest = root.join("deps/runtime/Cargo.toml");
    let text = fs::read_to_string(&manifest)
        .unwrap()
        .replace("license = \"MIT\"", "license = \"MIT AND Apache-2.0\"");
    fs::write(manifest, text).unwrap();
    fs::remove_file(root.join("deps/runtime/LICENSE")).unwrap();
    write(root, "deps/runtime/LICENSE-MIT", "Required MIT text");
    write(root, "deps/runtime/LICENSE-APACHE", "Required Apache text");
    generate(root.to_str().unwrap(), false).unwrap();
    let text = fs::read_to_string(root.join(OUTPUTS[0])).unwrap();
    assert!(text.contains("Required MIT text"));
    assert!(text.contains("Required Apache text"));
    assert!(!text.contains("Selected license: MIT"));
}

#[test]
fn catalog_resolves_sdk_metadata_and_each_dependency_license() {
    let directory = fixture();
    let root = directory.path();
    generate(root.to_str().unwrap(), false).unwrap();
    let paths = [
        "src/eigin_sdk/NOTICES.json",
        "src/eigin_sdk/apple/EiginSDK/Sources/EiginSDK/Resources/NOTICES.json",
    ];
    let original = fs::read_to_string(root.join(paths[0])).unwrap();
    let catalog: serde_json::Value = serde_json::from_str(&original).unwrap();
    assert_eq!(catalog["sdk"]["version"], "0.4.2");
    assert_eq!(catalog["sdk"]["license"], "AGPL-3.0");
    let texts = catalog["licenseTexts"].as_array().unwrap();
    let sdk_id = catalog["sdk"]["licenseIds"][0].as_u64().unwrap() as usize;
    assert_eq!(texts[sdk_id], "SDK license text");
    for package in catalog["packages"].as_array().unwrap() {
        let ids = package["licenseIds"].as_array().unwrap();
        assert!(!ids.is_empty());
        let bodies: Vec<_> = ids
            .iter()
            .map(|id| texts[id.as_u64().unwrap() as usize].as_str().unwrap())
            .collect();
        assert!(
            bodies.contains(&format!("License for {}", package["name"].as_str().unwrap()).as_str())
        );
        if package["name"] == "runtime" {
            assert!(
                package["notice"]
                    .as_str()
                    .unwrap()
                    .contains("Copyright runtime contributors")
            );
            assert!(
                package["notice"]
                    .as_str()
                    .unwrap()
                    .contains("Additional runtime attribution")
            );
        }
    }
    for path in paths {
        assert_eq!(fs::read_to_string(root.join(path)).unwrap(), original);
        fs::write(root.join(path), "stale").unwrap();
        assert!(generate(root.to_str().unwrap(), true).is_err());
        assert_eq!(fs::read_to_string(root.join(path)).unwrap(), "stale");
        fs::remove_file(root.join(path)).unwrap();
        assert!(generate(root.to_str().unwrap(), true).is_err());
        assert!(!root.join(path).exists());
        generate(root.to_str().unwrap(), false).unwrap();
        assert_eq!(fs::read_to_string(root.join(path)).unwrap(), original);
    }
    write(root, "config/app.toml", "[version]\nsdk = \"0.5.0\"\n");
    assert!(generate(root.to_str().unwrap(), true).is_err());
    generate(root.to_str().unwrap(), false).unwrap();
    let updated: serde_json::Value =
        serde_json::from_str(&fs::read_to_string(root.join(paths[0])).unwrap()).unwrap();
    assert_eq!(updated["sdk"]["version"], "0.5.0");
}

mod validation;
