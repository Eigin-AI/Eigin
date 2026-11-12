use super::super::types::*;
use base64::{Engine, engine::general_purpose::STANDARD};
use serde_json::{Value, json};

// Adapt native authentication without adding a Bearer credential to shared requests.
pub(super) fn config(mut config: InferenceProviderConfig) -> InferenceProviderConfig {
    let token = std::mem::take(&mut config.api_token);
    let mut headers = std::collections::HashMap::from([
        ("x-api-key".into(), token),
        ("anthropic-version".into(), "2023-06-01".into()),
    ]);
    for (key, value) in config.extra_headers {
        headers.insert(key.to_ascii_lowercase(), value);
    }
    config.extra_headers = headers;
    config
}

pub(super) fn encode(input: &InferenceCompletionInput) -> Result<Vec<u8>, InferenceError> {
    let system = input
        .messages
        .iter()
        .filter(|m| m.role == "system")
        .filter_map(|m| m.content.as_deref())
        .collect::<Vec<_>>()
        .join("\n\n");
    let mut messages: Vec<Value> = Vec::new();
    for message in input.messages.iter().filter(|m| m.role != "system") {
        let text = message.content.as_deref().unwrap_or("");
        let (role, content) = match message.role.as_str() {
            "assistant" => {
                let calls = message.tool_calls.as_deref().unwrap_or_default();
                if calls.is_empty() {
                    ("assistant", json!(text))
                } else {
                    let mut blocks = Vec::new();
                    if !text.is_empty() {
                        blocks.push(json!({"type":"text","text":text}));
                    }
                    for call in calls {
                        let arguments = serde_json::from_str::<Value>(&call.arguments)
                            .ok()
                            .filter(Value::is_object)
                            .unwrap_or_else(|| json!({}));
                        blocks.push(json!({"type":"tool_use","id":call.id,"name":call.name,"input":arguments}));
                    }
                    ("assistant", json!(blocks))
                }
            }
            "tool" => {
                let block = json!({"type":"tool_result","tool_use_id":message.tool_call_id.as_deref().unwrap_or(""),"content":text});
                if let Some(last) = messages.last_mut()
                    && last["role"] == "user"
                    && let Some(blocks) = last["content"].as_array_mut()
                    && blocks.iter().all(|b| b["type"] == "tool_result")
                {
                    blocks.push(block);
                    continue;
                }
                ("user", json!([block]))
            }
            _ => {
                let mut blocks = message.images.iter().map(|image| json!({
                    "type":"image", "source":{"type":"base64","media_type":image.mime_type,"data":STANDARD.encode(&image.bytes)}
                })).collect::<Vec<_>>();
                if (message.has_attachments || !blocks.is_empty()) && !text.is_empty() {
                    blocks.push(json!({"type":"text","text":text}));
                }
                (
                    "user",
                    if blocks.is_empty() {
                        json!(text)
                    } else {
                        json!(blocks)
                    },
                )
            }
        };
        messages.push(json!({"role":role,"content":content}));
    }
    let mut body = json!({"model":input.model,"max_tokens":8192,"cache_control":{"type":"ephemeral"},"messages":messages,"stream":true});
    if !system.is_empty() {
        body["system"] = json!(system);
    }
    if let Some(tools) = &input.tools {
        body["tools"] = tools.iter().map(|tool| {
            Ok(json!({"name":tool.name,"description":tool.description,"input_schema":serde_json::from_str::<Value>(&tool.parameters_json)?}))
        }).collect::<Result<Vec<_>, serde_json::Error>>()?.into();
    }
    Ok(serde_json::to_vec(&body)?)
}

pub(super) fn validation(model: &str) -> Vec<u8> {
    json!({"model":model,"max_tokens":1,"cache_control":{"type":"ephemeral"},"messages":[{"role":"user","content":"hi"}],"stream":false}).to_string().into_bytes()
}
