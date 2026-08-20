//! rotate-key — re-encrypt stored credit tokens onto a new `TOKEN_ENCRYPTION_KEY`.
//!
//! Used during a key rotation (see docs/src/runbooks/token-key-rotation.md). The relay
//! runs the new key as primary and the old key as secondary, then this tool sweeps every
//! wallet's `token_ciphertext` from the old key onto the new one. `check` confirms the
//! sweep has drained before the secondary is retired.
//!
//! Reuses the relay's real token crypto so ciphertexts and key fingerprints match exactly.
//! Reads `DATABASE_URL` from the environment.

use std::process::ExitCode;

use clap::{Parser, Subcommand};
use eigin_relay::credits::token;
use sqlx::{PgPool, Row};
use uuid::Uuid;

#[derive(Parser)]
#[command(name = "rotate-key", about = "Rotate the relay's token encryption key")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Re-encrypt every wallet not already on the new key. Idempotent and resumable.
    Sweep(SweepArgs),
    /// Fail if any wallet is still on a key other than the given one.
    Check(CheckArgs),
}

#[derive(Parser)]
struct SweepArgs {
    /// The new (primary) key, base64. Rows are re-encrypted onto this key.
    #[arg(long)]
    new_key: String,
    /// The old (previous) key, base64. Used to decrypt rows not yet on the new key.
    #[arg(long)]
    old_key: String,
    /// Report what would change without writing anything.
    #[arg(long)]
    dry_run: bool,
}

#[derive(Parser)]
struct CheckArgs {
    /// The current (primary) key, base64. Every row must be on this key.
    #[arg(long)]
    key: String,
}

type BoxError = Box<dyn std::error::Error>;

#[tokio::main]
async fn main() -> ExitCode {
    match run().await {
        Ok(code) => code,
        Err(e) => {
            eprintln!("error: {e}");
            ExitCode::FAILURE
        }
    }
}

async fn run() -> Result<ExitCode, BoxError> {
    let cli = Cli::parse();
    let database_url = std::env::var("DATABASE_URL")
        .map_err(|_| "DATABASE_URL must be set to the target relay database")?;
    let pool = PgPool::connect(&database_url).await?;

    match cli.command {
        Command::Sweep(args) => sweep(&pool, &args).await,
        Command::Check(args) => check(&pool, &args).await,
    }
}

async fn sweep(pool: &PgPool, args: &SweepArgs) -> Result<ExitCode, BoxError> {
    let new_key = token::parse_encryption_key(&args.new_key)?;
    let old_key = token::parse_encryption_key(&args.old_key)?;
    let new_fp = token::fingerprint(&new_key);

    // Only rows not already on the new key. Re-running naturally resumes where it left off.
    let rows = sqlx::query(
        "SELECT id, token_hash, token_ciphertext FROM wallets WHERE key_fp IS DISTINCT FROM $1",
    )
    .bind(&new_fp)
    .fetch_all(pool)
    .await?;

    println!(
        "{} wallet(s) to re-encrypt with key (hash) {new_fp}",
        rows.len()
    );

    let mut done = 0u64;
    let mut undecryptable: Vec<Uuid> = Vec::new();
    for row in &rows {
        let id: Uuid = row.try_get("id")?;
        let token_hash: String = row.try_get("token_hash")?;
        let ciphertext: String = row.try_get("token_ciphertext")?;

        // Prefer the new key (already-migrated but unstamped rows), else the old key.
        // A row that decrypts with neither was encrypted under some other key we weren't
        // given. Its credits still work (lookup is by token hash), but the stored token
        // can't be re-encrypted, and so can't be restored, without that key. That's a
        // pre-existing condition, not something to abort the whole sweep over: skip it,
        // record it, and keep migrating the rest.
        let plaintext = match token::decrypt(&ciphertext, &token_hash, &new_key)
            .or_else(|_| token::decrypt(&ciphertext, &token_hash, &old_key))
        {
            Ok(plaintext) => plaintext,
            Err(_) => {
                undecryptable.push(id);
                continue;
            }
        };

        if args.dry_run {
            continue;
        }

        let new_ciphertext = token::encrypt(&plaintext, &token_hash, &new_key)?;
        // Per-row atomic write. A crash mid-sweep leaves already-done rows on the new key.
        sqlx::query("UPDATE wallets SET token_ciphertext = $1, key_fp = $2 WHERE id = $3")
            .bind(&new_ciphertext)
            .bind(&new_fp)
            .bind(id)
            .execute(pool)
            .await?;
        done += 1;
    }

    if args.dry_run {
        let ok = rows.len() - undecryptable.len();
        println!(
            "dry run — {ok} would be re-encrypted, {} undecryptable",
            undecryptable.len()
        );
    } else {
        println!("re-encrypted {done} wallet(s)");
    }

    if undecryptable.is_empty() {
        Ok(ExitCode::SUCCESS)
    } else {
        eprintln!(
            "{} wallet(s) could not be decrypted with the new or old key and were left unchanged:",
            undecryptable.len()
        );
        for id in &undecryptable {
            eprintln!("  {id}");
        }
        eprintln!(
            "These were encrypted under a key not supplied here. Their credits still work, but \
             the token cannot be restored until it is re-encrypted with the key it was minted \
             under. Supply that key as --old-key and re-run, or handle these wallets manually."
        );
        Ok(ExitCode::FAILURE)
    }
}

async fn check(pool: &PgPool, args: &CheckArgs) -> Result<ExitCode, BoxError> {
    let key = token::parse_encryption_key(&args.key)?;
    let fp = token::fingerprint(&key);

    let stale: i64 = sqlx::query("SELECT count(*) FROM wallets WHERE key_fp IS DISTINCT FROM $1")
        .bind(&fp)
        .fetch_one(pool)
        .await?
        .try_get(0)?;

    if stale == 0 {
        println!("ok — every wallet is encrypted with key (hash) {fp}");
        Ok(ExitCode::SUCCESS)
    } else {
        eprintln!(
            "{stale} wallet(s) are not encrypted with key (hash) {fp} — run `rotate-key sweep` first"
        );
        Ok(ExitCode::FAILURE)
    }
}
