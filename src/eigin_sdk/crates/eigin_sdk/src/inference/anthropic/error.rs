use crate::inference::InferenceError;

pub(super) fn normalize(status: u16, body: Option<String>) -> InferenceError {
    let body = body
        .map(|text| text.split(['\r', '\n']).collect::<String>())
        .filter(|text| !text.is_empty());
    InferenceError::Http { status, body }
}
