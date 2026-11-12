use clap::{Args, ValueEnum};
use eigin_sdk::inference::*;
use std::{
    io,
    sync::{Arc, Mutex},
};

type Error = Box<dyn std::error::Error>;

#[derive(Clone, Copy, ValueEnum)]
enum ProviderKind {
    #[value(name = "openai-compatible")]
    OpenAiCompatible,
    #[value(name = "openai-responses")]
    OpenAiResponses,
    EiginRelay,
}

#[derive(Args)]
pub(crate) struct Connection {
    /// Versioned OpenAI endpoint, or relay root URL.
    #[arg(long)]
    base_url: String,
    #[arg(long, value_enum, default_value = "openai-compatible")]
    provider: ProviderKind,
    /// Read credentials from this environment variable, never from arguments.
    #[arg(long, conflicts_with = "no_auth")]
    api_key_env: Option<String>,
    /// Connect to an OpenAI-compatible endpoint without an API key.
    #[arg(long)]
    no_auth: bool,
    /// Read the relay application key from this environment variable.
    #[arg(long)]
    relay_key_env: Option<String>,
    /// Read a wallet token from this variable. Repeat in spending order.
    #[arg(long)]
    credit_token_env: Vec<String>,
}

impl Connection {
    pub(super) fn provider(self, chat: bool) -> Result<Provider, Error> {
        match self.provider {
            ProviderKind::OpenAiCompatible | ProviderKind::OpenAiResponses => {
                if self.relay_key_env.is_some() || !self.credit_token_env.is_empty() {
                    return Err(invalid(
                        "EiginRelay credentials require --provider eigin-relay",
                    ));
                }
                let api_token = match self.api_key_env {
                    Some(name) => secret(&name)?,
                    None if self.no_auth => String::new(),
                    None => return Err(invalid("Choose --api-key-env NAME or --no-auth")),
                };
                let config = InferenceProviderConfig {
                    base_url: self.base_url,
                    api_token,
                    extra_headers: Default::default(),
                };
                Ok(match self.provider {
                    ProviderKind::OpenAiResponses => {
                        Provider::OpenAiResponses(OpenAiResponsesProvider::new(config)?)
                    }
                    _ => Provider::OpenAiCompatible(OpenAiCompatibleProvider::new(config)?),
                })
            }
            ProviderKind::EiginRelay => {
                if self.api_key_env.is_some() || self.no_auth {
                    return Err(invalid(
                        "EiginRelay uses --relay-key-env and --credit-token-env, not --api-key-env or --no-auth",
                    ));
                }
                let key = self
                    .relay_key_env
                    .ok_or_else(|| invalid("EiginRelay requires --relay-key-env NAME"))?;
                if chat && self.credit_token_env.is_empty() {
                    return Err(invalid("EiginRelay chat requires --credit-token-env NAME"));
                }
                let tokens = self
                    .credit_token_env
                    .iter()
                    .map(|name| secret(name))
                    .collect::<Result<Vec<_>, _>>()?;
                Ok(Provider::EiginRelay(EiginRelayProvider::new(
                    EiginRelayProviderConfig {
                        base_url: self.base_url,
                        relay_key: secret(&key)?,
                    },
                    Box::new(Wallets(Mutex::new(tokens))),
                )?))
            }
        }
    }
}

fn invalid(message: &str) -> Error {
    io::Error::new(io::ErrorKind::InvalidInput, message).into()
}
fn secret(name: &str) -> Result<String, Error> {
    let value = std::env::var(name).map_err(|_| {
        invalid(&format!(
            "Environment variable {name} is missing or is not valid Unicode"
        ))
    })?;
    if value.trim().is_empty() {
        return Err(invalid(&format!("Environment variable {name} is empty")));
    }
    Ok(value)
}

struct Wallets(Mutex<Vec<String>>);
impl EiginRelayWalletSource for Wallets {
    fn next_token(&self, excluded: Vec<String>) -> Result<Option<String>, EiginRelayWalletError> {
        Ok(self
            .0
            .lock()
            .unwrap()
            .iter()
            .find(|t| !excluded.contains(t))
            .cloned())
    }
    fn mark_exhausted(&self, token: String) -> Result<(), EiginRelayWalletError> {
        self.0.lock().unwrap().retain(|t| t != &token);
        Ok(())
    }
}

pub(super) enum Provider {
    OpenAiCompatible(Arc<OpenAiCompatibleProvider>),
    OpenAiResponses(Arc<OpenAiResponsesProvider>),
    EiginRelay(Arc<EiginRelayProvider>),
}
impl Provider {
    pub(super) fn discovery(&self) -> Discovery {
        match self {
            Self::OpenAiCompatible(p) => Discovery::Compatible(p.discovery()),
            Self::OpenAiResponses(p) => Discovery::Responses(p.discovery()),
            Self::EiginRelay(p) => Discovery::Compatible(p.discovery()),
        }
    }
    pub(super) fn stream(&self, input: InferenceCompletionInput) -> Result<Stream, InferenceError> {
        match self {
            Self::OpenAiCompatible(p) => Ok(Stream::OpenAiCompatible(p.stream(input)?)),
            Self::OpenAiResponses(p) => Ok(Stream::OpenAiResponses(p.stream(input)?)),
            Self::EiginRelay(p) => Ok(Stream::EiginRelay(p.stream(input)?)),
        }
    }
}

#[derive(Clone)]
pub(super) enum Stream {
    OpenAiCompatible(Arc<OpenAiCompatibleStream>),
    OpenAiResponses(Arc<OpenAiResponsesStream>),
    EiginRelay(Arc<EiginRelayStream>),
}
impl Stream {
    pub(super) fn cancel(&self) {
        match self {
            Self::OpenAiCompatible(s) => s.cancel(),
            Self::OpenAiResponses(s) => s.cancel(),
            Self::EiginRelay(s) => s.cancel(),
        }
    }
    pub(super) async fn next(&self) -> Result<Option<InferenceEvent>, InferenceError> {
        match self {
            Self::OpenAiCompatible(s) => s.next().await,
            Self::OpenAiResponses(s) => s.next().await,
            Self::EiginRelay(s) => s.next().await,
        }
    }
}

#[derive(Clone)]
pub(super) enum Discovery {
    Compatible(Arc<ModelDiscoveryOperation>),
    Responses(Arc<OpenAiResponsesModelDiscovery>),
}
impl Discovery {
    pub(super) fn cancel(&self) {
        match self {
            Self::Compatible(op) => op.cancel(),
            Self::Responses(op) => op.cancel(),
        }
    }
    pub(super) async fn fetch_models(&self) -> Result<Vec<String>, InferenceError> {
        match self {
            Self::Compatible(op) => op.fetch_models().await,
            Self::Responses(op) => op.fetch_models().await,
        }
    }
}
