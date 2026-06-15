//! Grant faucet: generate an Ed25519 keypair and sign credit grant tokens.
//!
//! A grant is a JWT (`alg: EdDSA`) the relay verifies against the public key injected as
//! `GRANT_PUBLIC_KEY`. The private key stays local and never reaches the relay.

use std::fs;
use std::path::PathBuf;

use anyhow::{Context, Result};
use clap::{Args, Subcommand};
use ed25519_dalek::SigningKey;
use ed25519_dalek::pkcs8::EncodePrivateKey;
use ed25519_dalek::pkcs8::spki::EncodePublicKey;
use ed25519_dalek::pkcs8::spki::der::pem::LineEnding;
use jsonwebtoken::{Algorithm, EncodingKey, Header, encode, get_current_timestamp};
use serde::Serialize;

#[derive(Args)]
pub struct GrantArgs {
    #[command(subcommand)]
    command: GrantCommand,
}

#[derive(Subcommand)]
enum GrantCommand {
    /// Generate a new Ed25519 signing keypair.
    Keygen(KeygenArgs),
    /// Sign a grant token with a private key.
    Sign(SignArgs),
}

#[derive(Args)]
struct KeygenArgs {
    /// Directory to write `grant_private.pem` and `grant_public.pem` into.
    #[arg(long)]
    out_dir: PathBuf,
}

#[derive(Args)]
struct SignArgs {
    /// Path to the Ed25519 private key PEM. If omitted, the key is read from the
    /// GRANT_PRIVATE_KEY environment variable (so a key pulled from Terraform state
    /// need not be written to disk).
    #[arg(long)]
    private_key: Option<PathBuf>,
    /// Product ID to grant (must exist in the relay's products.toml).
    #[arg(long)]
    product: String,
    /// Issuer identifier; must match the relay's GRANT_ISSUER.
    #[arg(long, default_value = "eigin")]
    issuer: String,
    /// Days until the grant expires.
    #[arg(long, default_value_t = 365)]
    ttl_days: u64,
    /// Unique grant id (`jti`). Defaults to a random UUID.
    #[arg(long)]
    jti: Option<String>,
}

#[derive(Serialize)]
struct Claims {
    iss: String,
    jti: String,
    exp: u64,
    product_id: String,
}

pub fn run(args: GrantArgs) -> Result<()> {
    match args.command {
        GrantCommand::Keygen(args) => keygen(args),
        GrantCommand::Sign(args) => sign(args),
    }
}

fn keygen(args: KeygenArgs) -> Result<()> {
    let signing = SigningKey::generate(&mut rand::rngs::OsRng);
    let private_pem = signing
        .to_pkcs8_pem(LineEnding::LF)
        .context("encoding private key")?;
    let public_pem = signing
        .verifying_key()
        .to_public_key_pem(LineEnding::LF)
        .context("encoding public key")?;

    fs::create_dir_all(&args.out_dir)
        .with_context(|| format!("creating {}", args.out_dir.display()))?;
    let private_path = args.out_dir.join("grant_private.pem");
    let public_path = args.out_dir.join("grant_public.pem");
    fs::write(&private_path, private_pem.as_bytes())?;
    fs::write(&public_path, public_pem.as_bytes())?;

    println!(
        "Wrote {} and {}",
        private_path.display(),
        public_path.display()
    );
    println!(
        "\nThe public key is delivered to the relay as GRANT_PUBLIC_KEY. Keep \
         grant_private.pem secret; it can mint credits.\n\n{public_pem}"
    );
    Ok(())
}

fn sign(args: SignArgs) -> Result<()> {
    let pem = match &args.private_key {
        Some(path) => {
            fs::read_to_string(path).with_context(|| format!("reading {}", path.display()))?
        }
        None => std::env::var("GRANT_PRIVATE_KEY")
            .context("no --private-key given and GRANT_PRIVATE_KEY is not set")?,
    };
    let key = EncodingKey::from_ed_pem(pem.as_bytes()).context("loading private key")?;

    let claims = Claims {
        iss: args.issuer,
        jti: args.jti.unwrap_or_else(|| uuid::Uuid::new_v4().to_string()),
        exp: get_current_timestamp() + args.ttl_days * 86_400,
        product_id: args.product,
    };

    let token = encode(&Header::new(Algorithm::EdDSA), &claims, &key).context("signing grant")?;
    println!("{token}");
    Ok(())
}
