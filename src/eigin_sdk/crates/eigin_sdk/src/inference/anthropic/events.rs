use serde::Deserialize;

#[derive(Deserialize)]
pub(super) struct BlockStart {
    pub(super) index: i64,
    pub(super) content_block: Block,
}

#[derive(Deserialize)]
pub(super) struct Block {
    pub(super) r#type: String,
    pub(super) id: Option<String>,
    pub(super) name: Option<String>,
    #[allow(dead_code)]
    pub(super) text: Option<String>,
}

#[derive(Deserialize)]
pub(super) struct BlockDelta {
    pub(super) index: i64,
    pub(super) delta: Delta,
}

#[derive(Deserialize)]
pub(super) struct Delta {
    pub(super) r#type: String,
    pub(super) text: Option<String>,
    pub(super) partial_json: Option<String>,
}

#[derive(Deserialize)]
pub(super) struct BlockStop {
    pub(super) index: i64,
}

#[derive(Deserialize)]
pub(super) struct MessageDelta {
    pub(super) delta: StopReason,
}

#[derive(Deserialize)]
pub(super) struct StopReason {
    pub(super) stop_reason: Option<String>,
}

#[derive(Deserialize)]
pub(super) struct StreamError {
    pub(super) error: ErrorDetail,
}

#[derive(Deserialize)]
pub(super) struct ErrorDetail {
    pub(super) r#type: String,
    pub(super) message: String,
}
