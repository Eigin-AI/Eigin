use serde::Deserialize;

// Known fields reject malformed types; unknown fields remain forward-compatible.
#[derive(Deserialize)]
pub(super) struct Event {
    pub r#type: Option<String>,
    pub delta: Option<String>,
    pub item: Option<Item>,
    pub response: Option<Response>,
    pub code: Option<String>,
    pub message: Option<String>,
}

#[derive(Deserialize)]
pub(super) struct Item {
    pub r#type: Option<String>,
    pub call_id: Option<String>,
    pub name: Option<String>,
    pub arguments: Option<String>,
}

#[derive(Deserialize)]
pub(super) struct Response {
    pub error: Option<ApiError>,
    pub incomplete_details: Option<IncompleteDetails>,
    #[serde(rename = "usage")]
    pub _usage: Option<Usage>,
}

#[derive(Deserialize)]
pub(super) struct ApiError {
    pub code: Option<String>,
    pub message: Option<String>,
    pub param: Option<String>,
}

#[derive(Deserialize)]
pub(super) struct IncompleteDetails {
    pub reason: Option<String>,
}

#[derive(Deserialize)]
pub(super) struct Usage {
    #[serde(rename = "totalTokens")]
    pub _total_tokens: Option<i64>,
}
