//! One-off inference commands using the SDK's default HTTP transport.

mod connection;
use clap::{Subcommand, ValueEnum};
use connection::Connection;
use eigin_sdk::inference::*;
use std::io::{self, Write};

#[derive(Subcommand)]
pub(crate) enum Command {
    /// Discover models at the selected provider.
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

pub(crate) fn run(command: Command) -> Result<(), Box<dyn std::error::Error>> {
    match command {
        Command::Models(connection) => {
            let operation = connection.provider(false)?.discovery();
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
            let completion = connection
                .provider(true)?
                .stream(InferenceCompletionInput {
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
