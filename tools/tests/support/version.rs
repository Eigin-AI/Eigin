use std::{fs, path::Path};
use tempfile::TempDir;

pub const IOS: &str = "src/eigin_ios/project.yml";
pub const NPM: &str = "src/eigin_sdk/web/package.json";
pub const APP_TOML: &str = r#"
[version]
product = "1.0.0"
sdk = "0.1.0"

[identity]
bundle_id = "ai.example.app"

[contact]
support = "support@example"
alerts = "alerts@example"

[relay]
url.staging = "https://staging.example"
url.production = "https://example"

[oauth.google]
client_id.staging = ""
client_id.production = ""
[oauth.microsoft]
client_id.staging = ""
client_id.production = ""
[oauth.aula]
client_id.staging = ""
client_id.production = ""

[legal]
privacy = "https://www.example/privacy/"
terms = "https://www.example/terms/"
"#;

pub fn put(root: &Path, path: &str, content: &str) {
    let path = root.join(path);
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    fs::write(path, content).unwrap();
}

pub fn fixture() -> TempDir {
    let dir = TempDir::new().unwrap();
    let root = dir.path();
    put(root, "config/app.toml", APP_TOML);
    for (path, name, version, dependency) in [
        ("src/eigin_relay", "eigin-relay", "1.0.0", ""),
        (
            "src/eigin_cli",
            "eigin-cli",
            "1.0.0",
            "[dependencies]\neigin_sdk = { path = \"../eigin_sdk/crates/eigin_sdk\" }\n",
        ),
        ("src/eigin_sdk/crates/eigin_sdk", "eigin_sdk", "0.1.0", ""),
        ("tools", "eigin-tools", "0.1.0", ""),
    ] {
        put(
            root,
            &format!("{path}/Cargo.toml"),
            &format!(
                "[package]\nname = \"{name}\"\nversion = \"{version}\" # preserve\nedition = \"2021\"\n{dependency}"
            ),
        );
        put(root, &format!("{path}/src/lib.rs"), "");
    }
    put(
        root,
        "src/eigin_sdk/Cargo.toml",
        "[workspace]\nmembers = [\"crates/eigin_sdk\"]\nresolver = \"2\"\n",
    );
    for manifest in ["src/eigin_relay", "src/eigin_cli", "src/eigin_sdk", "tools"] {
        assert!(
            std::process::Command::new("cargo")
                .current_dir(root)
                .args([
                    "generate-lockfile",
                    "--offline",
                    "--manifest-path",
                    &format!("{manifest}/Cargo.toml")
                ])
                .output()
                .unwrap()
                .status
                .success()
        );
    }
    put(
        root,
        NPM,
        "{\n  \"name\": \"@eigin/sdk\",\n  \"version\": \"0.1.0\"\n}\n",
    );
    put(
        root,
        "package.json",
        "{\"private\":true,\"workspaces\":[\"src/eigin_sdk/web\"]}",
    );
    put(
        root,
        "package-lock.json",
        "{\"packages\":{\"src/eigin_sdk/web\":{\"version\":\"0.1.0\"}}}",
    );
    put(
        root,
        IOS,
        "settings:\n  MARKETING_VERSION: \"1.0.0\"\n  CURRENT_PROJECT_VERSION: \"17\"\ntarget:\n  MARKETING_VERSION: \"1.0.0\"\n",
    );
    dir
}
