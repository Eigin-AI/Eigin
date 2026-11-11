use super::super::types::*;
use super::{StreamParser, wire::ToolDelta};

impl StreamParser {
    pub(super) fn tool(&mut self, delta: &ToolDelta) {
        if let Some(signature) = delta
            .extra_content
            .as_ref()
            .and_then(|e| e.google.as_ref())
            .and_then(|g| g.thought_signature.as_ref())
        {
            self.metadata
                .insert("thought_signature".into(), signature.clone());
        }
        if delta.id.is_none() && delta.function.is_none() {
            return;
        }
        let key = if let Some(index) = delta.index {
            index
        } else if let Some(id) = &delta.id {
            self.calls
                .iter()
                .find(|(_, c)| &c.id == id)
                .map(|(k, _)| *k)
                .unwrap_or_else(|| {
                    let key = self.next_index;
                    self.next_index += 1;
                    key
                })
        } else {
            0
        };
        let call = self.calls.entry(key).or_insert_with(|| InferenceToolCall {
            kind: "function".into(),
            ..Default::default()
        });
        if let Some(id) = &delta.id {
            call.id = id.clone();
        }
        if let Some(kind) = &delta.kind {
            call.kind = kind.clone();
        }
        if let Some(function) = &delta.function {
            if let Some(name) = &function.name {
                call.name = name.clone();
            }
            if let Some(args) = &function.arguments {
                call.arguments.push_str(args);
            }
        }
    }
}
