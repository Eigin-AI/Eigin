use anyhow::{Context, Result, bail, ensure};
use sha2::{Digest, Sha256};
use std::process::{Command, Stdio};
use std::thread::sleep;
use std::time::Duration;
use uuid::Uuid;

const USER: &str = "contributors";

fn container_name(root: &str) -> String {
    let hash = hex::encode(Sha256::digest(root.as_bytes()));
    format!("eigin-contributors-{}", &hash[..16])
}

fn docker_output(args: &[&str]) -> Result<String> {
    let output = Command::new("docker")
        .args(args)
        .output()
        .context("contributor development requires Docker")?;
    ensure!(
        output.status.success(),
        "Docker could not set up contributor PostgreSQL: {}",
        String::from_utf8_lossy(&output.stderr).trim()
    );
    Ok(String::from_utf8(output.stdout)?.trim().to_owned())
}

/// Start or reuse a development database dedicated to this checkout.
pub fn start(root: &str) -> Result<String> {
    let name = container_name(root);
    let existing = docker_output(&[
        "ps",
        "-a",
        "--filter",
        &format!("name=^/{name}$"),
        "--format",
        "{{.State}}",
    ])?;
    if existing.is_empty() {
        let password = Uuid::new_v4().simple().to_string();
        docker_output(&[
            "run",
            "-d",
            "--name",
            &name,
            "-p",
            "127.0.0.1::5432",
            "-e",
            "POSTGRES_USER=contributors",
            "-e",
            "POSTGRES_DB=contributors",
            "-e",
            &format!("POSTGRES_PASSWORD={password}"),
            "postgres:16",
        ])?;
    } else if existing != "running" {
        docker_output(&["start", &name])?;
    }

    for _ in 0..60 {
        let ready = Command::new("docker")
            .args([
                "exec",
                &name,
                "pg_isready",
                "-h",
                "127.0.0.1",
                "-U",
                USER,
                "-d",
                USER,
                "-q",
            ])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()?;
        if ready.success() {
            let address = docker_output(&["port", &name, "5432/tcp"])?;
            let port = address
                .strip_prefix("127.0.0.1:")
                .and_then(|port| port.parse::<u16>().ok());
            ensure!(
                port.is_some_and(|port| port > 0),
                "contributor PostgreSQL must publish a loopback port"
            );
            let password = docker_output(&["exec", &name, "printenv", "POSTGRES_PASSWORD"])?;
            ensure!(
                password.len() == 32 && password.bytes().all(|byte| byte.is_ascii_hexdigit()),
                "contributor PostgreSQL has unexpected credentials"
            );
            return Ok(format!("postgresql://{USER}:{password}@{address}/{USER}"));
        }
        sleep(Duration::from_secs(1));
    }
    bail!("contributor PostgreSQL did not become ready; check `docker logs {name}`");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    #[ignore = "requires Docker and the portal's npm dependencies"]
    fn local_database_is_migrated_and_reused() -> Result<()> {
        struct Remove(String);
        impl Drop for Remove {
            fn drop(&mut self) {
                let _ = docker_output(&["rm", "-fv", &self.0]);
            }
        }
        let root = tempfile::tempdir()?;
        let root = root.path().to_str().context("invalid test path")?;
        let name = container_name(root);
        let _cleanup = Remove(name.clone());
        let url = start(root)?;
        let repo = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .unwrap();
        let migrate = || -> Result<()> {
            let status = Command::new("npm")
                .current_dir(repo)
                .args(["run", "db:migrate", "--workspace", "@eigin/contributors"])
                .env("DATABASE_URL", start(root)?)
                .status()?;
            ensure!(status.success(), "migration failed");
            Ok(())
        };
        migrate()?;
        docker_output(&["stop", &name])?;
        migrate()?;
        let applied = docker_output(&[
            "exec",
            &name,
            "psql",
            "-U",
            USER,
            "-d",
            USER,
            "-Atc",
            "SELECT count(*) FROM migrations",
        ])?;
        ensure!(applied.parse::<u32>()? >= 9, "migrations missing");
        ensure!(
            url.split('@').next() == start(root)?.split('@').next(),
            "database credentials changed"
        );
        Ok(())
    }
}
