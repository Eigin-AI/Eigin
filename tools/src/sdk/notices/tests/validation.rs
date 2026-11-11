use super::{OUTPUTS, fixture, generate, write};
use std::fs;

#[test]
fn empty_license_texts_fail_without_changing_bundled_outputs() {
    let directory = fixture();
    let root = directory.path();
    let mut lock: serde_json::Value =
        serde_json::from_str(&fs::read_to_string(root.join("package-lock.json")).unwrap()).unwrap();
    lock["packages"]["src/eigin_sdk/web"]["dependencies"]["@ubjs/core"] = "0.31.0-6".into();
    lock["packages"]["node_modules/@ubjs/core"] = serde_json::json!({"version": "0.31.0-6"});
    write(root, "package-lock.json", &lock.to_string());
    write(
        root,
        "node_modules/@ubjs/core/package.json",
        &serde_json::json!({
            "name": "@ubjs/core", "version": "0.31.0-6", "license": "MPL-2.0"
        })
        .to_string(),
    );
    write(root, "LICENSES/uniffi/MPL-2.0.txt", "Full fallback license");
    generate(root.to_str().unwrap(), false).unwrap();
    let snapshots: Vec<_> = OUTPUTS
        .iter()
        .copied()
        .chain([
            "src/eigin_sdk/NOTICES.json",
            "src/eigin_sdk/apple/EiginSDK/Sources/EiginSDK/Resources/NOTICES.json",
        ])
        .map(|path| (path, fs::read(root.join(path)).unwrap()))
        .collect();

    for path in [
        "deps/runtime/LICENSE",
        "node_modules/browser-runtime/LICENSE",
        "LICENSES/uniffi/MPL-2.0.txt",
        "LICENSE",
    ] {
        let original = fs::read(root.join(path)).unwrap();
        for body in ["", " \n\t\r\n"] {
            write(root, path, body);
            for check in [false, true] {
                let error = generate(root.to_str().unwrap(), check).unwrap_err();
                assert!(
                    error.to_string().contains("Empty license text"),
                    "{path}: {error:#}"
                );
                for (output, bytes) in &snapshots {
                    assert_eq!(&fs::read(root.join(output)).unwrap(), bytes);
                }
            }
        }
        fs::write(root.join(path), original).unwrap();
    }
    generate(root.to_str().unwrap(), true).unwrap();
}

#[test]
fn includes_unlicense_alone_and_alongside_mit() {
    let directory = fixture();
    let root = directory.path();
    for (name, expression) in [("runtime", "Unlicense"), ("transitive", "Unlicense OR MIT")] {
        let manifest = root.join(format!("deps/{name}/Cargo.toml"));
        let text = fs::read_to_string(&manifest)
            .unwrap()
            .replace("license = \"MIT\"", &format!("license = {expression:?}"));
        fs::write(manifest, text).unwrap();
        write(
            root,
            &format!("deps/{name}/UNLICENSE"),
            &format!("Unlicense terms for {name}"),
        );
    }
    fs::remove_file(root.join("deps/runtime/LICENSE")).unwrap();
    generate(root.to_str().unwrap(), false).unwrap();
    let text = fs::read_to_string(root.join(OUTPUTS[0])).unwrap();
    assert!(text.contains("Unlicense terms for runtime"));
    assert!(text.contains("Unlicense terms for transitive"));
    assert!(text.contains("License for transitive"));
    let catalog: serde_json::Value =
        serde_json::from_str(&fs::read_to_string(root.join("src/eigin_sdk/NOTICES.json")).unwrap())
            .unwrap();
    for name in ["runtime", "transitive"] {
        let package = catalog["packages"]
            .as_array()
            .unwrap()
            .iter()
            .find(|package| package["name"] == name)
            .unwrap();
        let texts: Vec<_> = package["licenseIds"]
            .as_array()
            .unwrap()
            .iter()
            .map(|id| {
                catalog["licenseTexts"][id.as_u64().unwrap() as usize]
                    .as_str()
                    .unwrap()
            })
            .collect();
        assert!(texts.contains(&format!("Unlicense terms for {name}").as_str()));
        if name == "transitive" {
            assert!(texts.contains(&"License for transitive"));
        }
    }
    generate(root.to_str().unwrap(), true).unwrap();
}
