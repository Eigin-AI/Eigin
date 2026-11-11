use super::{adapters::Adapter, types::*};
use serde_json::{Value, json};

impl Adapter {
    pub fn request(self, input: &InferenceCompletionInput) -> Result<Vec<u8>, InferenceError> {
        let messages: Vec<Value> = input
            .messages
            .iter()
            .map(|m| self.encode_message(m, input.reasoning_origin.as_ref()))
            .collect();
        let mut body = json!({"model": input.model, "messages": messages, "stream": true});
        if !input.text_only {
            if let Some(effort) = &input.reasoning_effort {
                body["reasoning_effort"] = json!(effort);
            }
            if !matches!(self, Self::Gemini | Self::OpenRouterAnthropic)
                && let Some(key) = &input.prompt_cache_key
            {
                body["prompt_cache_key"] = json!(key);
            }
            if let Some(tools) = &input.tools {
                body["tools"] = json!(
                    tools
                        .iter()
                        .map(encode_tool)
                        .collect::<Result<Vec<_>, _>>()?
                );
            }
        }
        if matches!(self, Self::OpenRouterAnthropic) {
            body["cache_control"] = json!({"type":"ephemeral"});
        }
        Ok(serde_json::to_vec(&body)?)
    }
}

fn encode_tool(tool: &InferenceToolDefinition) -> Result<Value, InferenceError> {
    let parameters: Value = serde_json::from_str(&tool.parameters_json)?;
    if !parameters.is_object() {
        return Err(InferenceError::InvalidData {
            reason: "tool parameters must be an object".into(),
        });
    }

    Ok(json!({
        "type": "function",
        "function": { "name": tool.name, "description": tool.description, "parameters": parameters }
    }))
}
