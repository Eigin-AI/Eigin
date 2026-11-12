use crate::inference::{InferenceError, InferenceEvent};
use std::collections::VecDeque;

#[derive(Default)]
pub(crate) struct ParsedEvents {
    pub events: VecDeque<InferenceEvent>,
    pub error: Option<InferenceError>,
    pub done: bool,
    pub refused: bool,
}

pub(crate) trait EventParser: Send {
    fn output(&self) -> &ParsedEvents;
    fn output_mut(&mut self) -> &mut ParsedEvents;
    fn line(&mut self, line: &[u8]);
    fn eof(&mut self);
}
