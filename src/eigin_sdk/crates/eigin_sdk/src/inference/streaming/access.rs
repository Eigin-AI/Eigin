use super::*;

pub(super) struct StreamState<P> {
    pub(super) request: Option<HttpRequest>,
    pub(super) parser: P,
    pub(super) buffer: SseBuffer,
    pub(super) opened: bool,
    pub(super) failure: Option<InferenceError>,
    pub(super) first_event: bool,
}

impl<P: EventParser> InferenceStream<P> {
    pub(super) fn lease(&self) -> Result<StreamAccessGuard<'_, P>, InferenceError> {
        if self.cancelled.load(Ordering::Acquire) {
            return Err(InferenceError::Cancelled);
        }
        let core = self
            .core
            .lock()
            .unwrap()
            .take()
            .ok_or(InferenceError::Busy)?;
        Ok(StreamAccessGuard {
            owner: self,
            core: Some(core),
            completed: false,
        })
    }
}

pub(super) struct StreamAccessGuard<'a, P: EventParser> {
    owner: &'a InferenceStream<P>,
    pub(super) core: Option<StreamState<P>>,
    pub(super) completed: bool,
}

impl<P: EventParser> Drop for StreamAccessGuard<'_, P> {
    fn drop(&mut self) {
        *self.owner.core.lock().unwrap() = self.core.take();
        if !self.completed {
            self.owner.cancel();
        }
    }
}
