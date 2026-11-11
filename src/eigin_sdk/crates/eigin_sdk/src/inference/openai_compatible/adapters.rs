use super::types::*;

const GEMINI_HOST: &str = "generativelanguage.googleapis.com";
const MISTRAL_HOST: &str = "api.mistral.ai";
const OPENROUTER_HOST: &str = "openrouter.ai";

#[derive(Clone, Copy, Debug)]
pub(super) enum Adapter {
    Default,
    Gemini,
    Mistral { reasoning: bool },
    OpenRouterAnthropic,
}

impl Adapter {
    pub fn select(base: &str, input: &InferenceCompletionInput) -> Self {
        if base.contains(GEMINI_HOST) {
            return Self::Gemini;
        }
        if url::Url::parse(base)
            .ok()
            .and_then(|u| u.host_str().map(str::to_owned))
            .as_deref()
            == Some(MISTRAL_HOST)
        {
            return Self::Mistral { reasoning: true };
        }
        match input.model_family {
            Some(InferenceModelFamily::Google) => Self::Gemini,
            Some(InferenceModelFamily::Mistral) => Self::Mistral {
                reasoning: input.is_relay,
            },
            Some(InferenceModelFamily::Anthropic) if base.contains(OPENROUTER_HOST) => {
                Self::OpenRouterAnthropic
            }
            _ => Self::Default,
        }
    }
}
