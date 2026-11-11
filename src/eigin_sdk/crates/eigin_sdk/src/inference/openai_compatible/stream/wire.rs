use super::super::types::InferenceError;
use serde::Deserialize;
use serde_json::Value;

#[derive(Deserialize)]
pub(super) struct CompletionChunk {
    pub(super) choices: Vec<CompletionChoice>,
}

#[derive(Deserialize)]
pub(super) struct CompletionChoice {
    pub(super) delta: CompletionDelta,
    pub(super) finish_reason: Option<String>,
}

#[derive(Deserialize)]
pub(super) struct CompletionDelta {
    pub(super) content: Option<Value>,
    pub(super) refusal: Option<String>,
    pub(super) tool_calls: Option<Vec<ToolDelta>>,
}

#[derive(Deserialize)]
pub(super) struct ToolDelta {
    pub(super) index: Option<i64>,
    pub(super) id: Option<String>,
    #[serde(rename = "type")]
    pub(super) kind: Option<String>,
    pub(super) function: Option<FunctionDelta>,
    pub(super) extra_content: Option<ExtraContent>,
}

#[derive(Deserialize)]
pub(super) struct FunctionDelta {
    pub(super) name: Option<String>,
    pub(super) arguments: Option<String>,
}

#[derive(Deserialize)]
pub(super) struct ExtraContent {
    pub(super) google: Option<GoogleExtra>,
}

#[derive(Deserialize)]
pub(super) struct GoogleExtra {
    pub(super) thought_signature: Option<String>,
}

pub(super) fn project_content(content: Option<&Value>) -> Result<Option<String>, InferenceError> {
    let Some(content) = content else {
        return Ok(None);
    };
    if content.is_null() {
        return Ok(None);
    }
    if let Some(text) = content.as_str() {
        return Ok(Some(text.into()));
    }
    #[derive(Deserialize)]
    struct TextPart {
        #[serde(rename = "type")]
        kind: String,
        text: Option<String>,
    }
    let parts: Vec<TextPart> = serde_json::from_value(content.clone())?;
    let texts: Vec<_> = parts
        .into_iter()
        .filter(|p| p.kind == "text")
        .filter_map(|p| p.text)
        .collect();
    Ok((!texts.is_empty()).then(|| texts.concat()))
}
