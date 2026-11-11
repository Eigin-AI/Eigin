//! One-off inference commands using the SDK's default HTTP transport.

use clap::{Args, Subcommand, ValueEnum};
use eigin_sdk::inference::*;
use std::io::{self, Write};

#[derive(Subcommand)]
pub(crate) enum Command {
    /// Discover models at an OpenAI-compatible endpoint.
    Models(Connection),
    /// Stream a completion using the SDK's default native HTTP transport.
    Chat {
        #[command(flatten)]
        connection: Connection,
        #[arg(long)]
        model: String,
        #[arg(long)]
        prompt: String,
        /// Family hint for models accessed through a router.
        #[arg(long, value_enum)]
        family: Option<Family>,
    },
}

#[derive(Args)]
pub(crate) struct Connection {
    /// Endpoint including its version prefix, e.g. http://127.0.0.1:8089/v1.
    #[arg(long)]
    base_url: String,
    /// Read credentials from this environment variable; never pass keys as arguments.
    #[arg(long, required_unless_present = "no_auth", conflicts_with = "no_auth", value_parser = clap::builder::NonEmptyStringValueParser::new())]
    api_key_env: Option<String>,
    /// Connect without sending an API key.
    #[arg(long)]
    no_auth: bool,
}

#[derive(Clone, Copy, ValueEnum)]
pub(crate) enum Family {
    Google,
    Mistral,
    Anthropic,
    Other,
}
impl From<Family> for InferenceModelFamily {
    fn from(family: Family) -> Self {
        match family {
            Family::Google => Self::Google,
            Family::Mistral => Self::Mistral,
            Family::Anthropic => Self::Anthropic,
            Family::Other => Self::Other,
        }
    }
}

impl Connection {
    fn provider(
        self,
    ) -> Result<std::sync::Arc<OpenAiCompatibleProvider>, Box<dyn std::error::Error>> {
        let api_token = match self.api_key_env {
            Some(name) => {
                let value = std::env::var(&name).map_err(|_| {
                    io::Error::new(
                        io::ErrorKind::InvalidInput,
                        format!("Environment variable {name} is missing or is not valid Unicode"),
                    )
                })?;
                if value.trim().is_empty() {
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidInput,
                        format!("Environment variable {name} is empty"),
                    )
                    .into());
                }
                value
            }
            None if self.no_auth => String::new(),
            None => {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    "Choose --api-key-env NAME or --no-auth",
                )
                .into());
            }
        };

        Ok(OpenAiCompatibleProvider::new(InferenceProviderConfig {
            base_url: self.base_url,
            api_token,
            extra_headers: Default::default(),
        })?)
    }
}

pub(crate) fn run(command: Command) -> Result<(), Box<dyn std::error::Error>> {
    match command {
        Command::Models(connection) => {
            let operation = connection.provider()?.discovery();
            let cancel = operation.clone();
            ctrlc::set_handler(move || cancel.cancel())?;
            for model in futures::executor::block_on(operation.fetch_models())? {
                println!("{model}");
            }
        }
        Command::Chat {
            connection,
            model,
            prompt,
            family,
        } => {
            let completion = connection.provider()?.stream(InferenceCompletionInput {
                model,
                model_family: family.map(Into::into),
                messages: vec![InferenceMessage {
                    role: "user".into(),
                    content: Some(prompt),
                    ..Default::default()
                }],
                ..Default::default()
            })?;
            let cancel = completion.clone();
            ctrlc::set_handler(move || cancel.cancel())?;
            futures::executor::block_on(async {
                while let Some(event) = completion.next().await? {
                    match event {
                        InferenceEvent::ContentDelta { text } => {
                            print!("{text}");
                            io::stdout().flush()?;
                        }
                        InferenceEvent::ToolCall { call } => {
                            println!("{}", serde_json::to_string(&call)?)
                        }
                        _ => {}
                    }
                }
                println!();
                Ok::<_, Box<dyn std::error::Error>>(())
            })?;
        }
    }
    Ok(())
}
