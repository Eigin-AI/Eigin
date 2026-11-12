use super::super::types::*;
use base64::{Engine, engine::general_purpose::STANDARD};
use serde_json::{Value, json};

pub(super) fn encode(input: &InferenceCompletionInput) -> Result<Vec<u8>, InferenceError> {
    let mut instructions = Vec::new();
    let mut items = Vec::new();
    for message in &input.messages {
        match message.role.as_str() {
            "system" | "developer" => {
                if let Some(text) = &message.content {
                    instructions.push(text.as_str());
                }
            }
            "assistant" => {
                if let Some(text) = &message.content
                    && !text.is_empty()
                {
                    items.push(json!({"type":"message", "role":"assistant", "content":[{"type":"output_text", "text":text}]}));
                }
                for call in message.tool_calls.iter().flatten() {
                    items.push(json!({"type":"function_call", "call_id":call.id, "name":call.name, "arguments":call.arguments}));
                }
            }
            "tool" => {
                if let Some(id) = &message.tool_call_id {
                    items.push(json!({"type":"function_call_output", "call_id":id, "output":message.content.as_deref().unwrap_or("")}));
                }
            }
            _ => {
                let mut parts = Vec::new();
                if let Some(text) = &message.content
                    && !text.is_empty()
                {
                    parts.push(json!({"type":"input_text", "text":text}));
                }
                for image in &message.images {
                    parts.push(json!({"type":"input_image", "image_url":format!("data:{};base64,{}", image.mime_type, STANDARD.encode(&image.bytes))}));
                }
                if parts.is_empty()
                    && let Some(text) = &message.content
                {
                    parts.push(json!({"type":"input_text", "text":text}));
                }
                items.push(json!({"type":"message", "role":message.role, "content":parts}));
            }
        }
    }
    let mut body = json!({"model":input.model, "input":items, "store":false, "stream":true});
    if !instructions.is_empty() {
        body["instructions"] = json!(instructions.join("\n\n"));
    }
    if let Some(tools) = &input.tools {
        body["tools"] = Value::Array(
            tools
                .iter()
                .map(|tool| {
                    Ok(
                        json!({"type":"function", "name":tool.name, "description":tool.description,
                "parameters":serde_json::from_str::<Value>(&tool.parameters_json)?}),
                    )
                })
                .collect::<Result<_, serde_json::Error>>()?,
        );
    }
    Ok(serde_json::to_vec(&body)?)
}
