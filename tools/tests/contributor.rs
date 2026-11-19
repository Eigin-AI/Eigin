//! Production workflow checks with an isolated filesystem and fake cloud commands.
use std::{
    fs,
    io::Write,
    os::unix::fs::PermissionsExt,
    process::{Command, Stdio},
};
use tempfile::TempDir;

fn attempt(failure: &str, confirm: bool) -> (bool, String) {
    attempt_action(failure, confirm, "after-apply")
}

fn attempt_action(failure: &str, confirm: bool, action: &str) -> (bool, String) {
    let dir = TempDir::new().unwrap();
    let root = dir.path();
    let receipts = root.join("infra/scaleway/contributor-releases");
    fs::create_dir_all(&receipts).unwrap();
    if failure != "no-receipt" {
        fs::write(
            receipts.join(format!("{}.brief", "a".repeat(64))),
            if failure == "gated" { "404" } else { "200" },
        )
        .unwrap();
    }
    let bin = root.join("bin");
    fs::create_dir(&bin).unwrap();
    let script = r#"#!/bin/sh
set -eu
exe=$(basename "$0")
printf '%s %s\n' "$exe" "$*" >> trace
case "$exe" in
 git) pwd ;;
 terraform) test "$TF_WORKSPACE" = production; printf '{"repo":"%s","region":"fr-par","project":"project","service":"svc","migrate":"mig","prune":"clean","digest":"%s"}' "$REPO" "$NEW" ;;
 scw) case "$*" in
    'jobs definition get '*) echo '{"project_id":"project"}' ;;
    'container container get '*) printf '{"registry_image":"%s@%s","privacy":"public","status":"ready"}' "$REPO" "$OLD" ;;
    'container container update '*) echo '{"status":"ready"}' ;;
    'jobs definition start '*) if [ "$FAIL" = migrate ]; then echo '{"state":"failed"}'; else echo '{"state":"succeeded"}'; fi ;;
    'jobs definition update '*) echo '{}' ;;
    *) exit 2;; esac ;;
 curl) case "$*" in
    *--head*) [ "$FAIL" != dns ] || exit 6 ;;
    */healthz) if { [ "$FAIL" = probe ] || [ "$FAIL" = bad-restore ]; } && [ ! -f failed ]; then touch failed; echo 503; else echo 200; fi ;;
    */review/calls/tool-safety) echo 404 ;;
    */calls/tool-safety) if [ "$FAIL" = gated ] || [ "$FAIL" = bad-restore ]; then echo 404; else echo 200; fi ;;
    */auth/gitlab) echo '303 https://code.eigin.ai/oauth/authorize?test=1' ;;
    */) echo 200 ;; *) exit 2 ;; esac ;;
esac"#;
    for name in ["git", "terraform", "docker", "npm", "just", "scw", "curl"] {
        let path = bin.join(name);
        fs::write(&path, script).unwrap();
        fs::set_permissions(path, fs::Permissions::from_mode(0o755)).unwrap();
    }
    let mut child = Command::new(env!("CARGO_BIN_EXE_eigin-tools"))
        .args(["contributor", action])
        .current_dir(root)
        .env("PATH", format!("{}:/usr/bin:/bin", bin.display()))
        .env(
            "REPO",
            "rg.fr-par.scw.cloud/eigin-production-contributor/portal",
        )
        .env(
            "OLD",
            format!(
                "sha256:{}",
                (if failure == "unchanged" { "b" } else { "a" }).repeat(64)
            ),
        )
        .env("NEW", format!("sha256:{}", "b".repeat(64)))
        .env(
            "EIGIN_DEPLOY_HANDOFF",
            if failure == "standalone" {
                ""
            } else {
                "production"
            },
        )
        .env("FAIL", failure)
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .unwrap();
    writeln!(
        child.stdin.take().unwrap(),
        "{}",
        if confirm { "yes" } else { "no" }
    )
    .unwrap();
    (
        child.wait().unwrap().success(),
        fs::read_to_string(root.join("trace")).unwrap_or_default(),
    )
}

#[test]
fn removed_release_subcommand_cannot_change_the_service() {
    let (ok, log) = attempt_action("", false, "release");
    assert!(!ok);
    assert!(!log.contains("docker ") && !log.contains("scw "));
}
#[test]
fn migration_failure_leaves_service_unchanged() {
    let (ok, log) = attempt("migrate", true);
    assert!(!ok);
    assert!(log.contains("jobs definition start"));
    assert!(!log.contains("container container update"));
}
#[test]
fn successful_release_migrates_before_switch_and_verifies_before_cleanup_update() {
    let (ok, log) = attempt("", true);
    assert!(ok, "{log}");
    assert!(
        log.find("definition start").unwrap() < log.find("container container update").unwrap()
    );
    assert!(!log.contains("docker "));
    assert!(log.contains(&format!(
        "image-uri=rg.fr-par.scw.cloud/eigin-production-contributor/portal@sha256:{}",
        "b".repeat(64)
    )));
    assert!(log.find("/auth/gitlab").unwrap() < log.find("definition update clean").unwrap());
}
#[test]
fn failed_probe_restores_previous_image() {
    let (ok, log) = attempt("probe", true);
    assert!(!ok);
    let updates: Vec<_> = log
        .lines()
        .filter(|l| l.contains("container container update"))
        .collect();
    assert_eq!(updates.len(), 2);
    assert!(updates[1].contains(&"a".repeat(64)));
}

#[test]
fn unreachable_domain_stops_before_cloud_changes() {
    let (ok, log) = attempt("dns", true);
    assert!(!ok);
    assert!(!log.contains("container container update") && !log.contains("jobs definition start"));
}

#[test]
fn production_deploy_finishes_without_a_second_prompt() {
    let (ok, log) = attempt_action("", false, "after-apply");
    assert!(
        ok && log.contains("jobs definition start") && log.contains("container container update")
    );
    let (ok, log) = attempt_action("unchanged", false, "after-apply");
    assert!(
        ok && !log.contains("jobs definition start") && !log.contains("container container update")
    );
}

#[test]
fn standalone_after_apply_cannot_touch_production() {
    let (ok, log) = attempt("standalone", false);
    assert!(!ok && log.is_empty());
}
#[test]
fn gated_previous_image_recovers_with_closed_brief() {
    let (ok, log) = attempt("gated", true);
    assert!(!ok);
    assert_eq!(log.matches("container container update").count(), 2);
    assert_eq!(
        log.lines().filter(|s| s.ends_with("/auth/gitlab")).count(),
        1
    );
}

#[test]
fn unknown_digest_stops_before_migrations() {
    let (ok, log) = attempt("no-receipt", false);
    assert!(!ok);
    assert!(!log.contains("jobs definition start"));
}
#[test]
fn restored_open_brief_must_not_return_404() {
    let (ok, log) = attempt("bad-restore", false);
    assert!(!ok);
    assert_eq!(log.matches("container container update").count(), 2);
    assert!(!log.contains("/auth/gitlab"));
}
