use access::StreamState;
mod access;
use super::{inference_diagnostics::InferenceDiagnostics, types::*};
use buffer::SseBuffer;
pub(crate) use http_failure::HttpFailurePolicy;
pub(crate) use parser::{EventParser, ParsedEvents};
mod buffer;
mod http_failure;
mod parser;
use crate::http::*;
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicBool, Ordering},
};

pub(crate) enum OpenFailureDelivery {
    Once,
    Repeat,
}

/// Shared HTTP lifecycle for pull-based inference streams.
pub(crate) struct InferenceStream<P: EventParser> {
    http: Arc<HttpOperation>,
    core: Mutex<Option<StreamState<P>>>,
    cancelled: AtomicBool,
    diagnostics: InferenceDiagnostics,
    model: String,
    http_failure: HttpFailurePolicy,
    open_failure_delivery: OpenFailureDelivery,
}

impl<P: EventParser> InferenceStream<P> {
    pub fn new(
        http: Arc<HttpOperation>,
        request: HttpRequest,
        model: String,
        parser: P,
        category: &'static str,
        http_failure: HttpFailurePolicy,
        open_failure_delivery: OpenFailureDelivery,
    ) -> Self {
        Self {
            http,
            core: Mutex::new(Some(StreamState {
                request: Some(request),
                parser,
                buffer: SseBuffer::default(),
                opened: false,
                failure: None,
                first_event: true,
            })),
            cancelled: AtomicBool::new(false),
            diagnostics: InferenceDiagnostics::for_provider("stream", category),
            model,
            http_failure,
            open_failure_delivery,
        }
    }

    async fn ensure_open(&self, core: &mut StreamState<P>) -> Result<(), InferenceError> {
        if let Some(error) = &core.failure {
            return Err(error.clone());
        }
        if core.opened {
            return Ok(());
        }
        self.diagnostics.start(Some(&self.model));
        let request = core.request.take().ok_or(InferenceError::Busy)?;
        let head = self.http.send(request).await?;
        self.diagnostics.headers(head.status);
        if !(200..300).contains(&head.status) {
            let error = self
                .http_failure
                .read(&self.http, head.status, &self.diagnostics)
                .await;
            self.http.cancel();
            return Err(error);
        }
        core.opened = true;
        Ok(())
    }
}

impl<P: EventParser> InferenceStream<P> {
    /// Opens HTTP and validates status without consuming successful response data.
    pub async fn open(&self) -> Result<(), InferenceError> {
        let mut lease = self.lease()?;
        let core = lease.core.as_mut().unwrap();
        let result = self.ensure_open(core).await;
        lease.completed = true;
        if let Err(error) = &result {
            core.failure = Some(error.clone());
            core.parser.output_mut().done = true;

            self.diagnostics.finish("request failed");
            self.http.cancel();
        }
        result
    }

    /// Produces the next ordered event, opening HTTP lazily if needed.
    pub async fn next(&self) -> Result<Option<InferenceEvent>, InferenceError> {
        let mut lease = self.lease()?;
        let core = lease.core.as_mut().unwrap();
        let result = async {
            if matches!(self.open_failure_delivery, OpenFailureDelivery::Repeat)
                && !core.opened
                && let Some(error) = &core.failure
            {
                return Err(error.clone());
            }
            if core.parser.output().done
                && core.parser.output().events.is_empty()
                && core.parser.output().error.is_none()
            {
                self.diagnostics.finish("request finished");
                return Ok(None);
            }
            self.ensure_open(core).await?;
            loop {
                if self.cancelled.load(Ordering::Acquire) {
                    return Err(InferenceError::Cancelled);
                }
                if let Some(event) = core.parser.output_mut().events.pop_front() {
                    self.diagnostics.event();
                    if core.first_event {
                        self.diagnostics.record(
                            "first event",
                            Some(&self.model),
                            match &event {
                                InferenceEvent::ContentDelta { text } => Some(text),
                                _ => None,
                            },
                        );
                        core.first_event = false;
                    }
                    if matches!(event, InferenceEvent::Finished { .. }) {
                        self.diagnostics.finish("request finished");
                    }
                    return Ok(Some(event));
                }
                if let Some(error) = core.parser.output_mut().error.take() {
                    core.parser.output_mut().done = true;
                    return Err(error);
                }
                if core.parser.output().done {
                    self.diagnostics.finish("request finished");
                    return Ok(None);
                }
                if let Some(line) = core.buffer.line()? {
                    core.parser.line(&line);
                    if core.parser.output().done || core.parser.output().error.is_some() {
                        self.http.cancel();
                    }
                    continue;
                }
                match self.http.read().await {
                    Ok(Some(chunk)) => {
                        self.diagnostics.chunk(chunk.len());
                        core.buffer.push(chunk)?;
                    }
                    Ok(None) => {
                        let remaining = core.buffer.remaining();
                        if !remaining.is_empty() {
                            core.parser.line(&remaining);
                        }
                        core.parser.eof();

                        self.http.cancel();
                    }
                    Err(error) => {
                        return Err(if core.parser.output().refused {
                            InferenceError::PolicyStop
                        } else {
                            error.into()
                        });
                    }
                }
            }
        }
        .await;
        lease.completed = true;
        if let Err(error) = &result {
            self.diagnostics.finish("request failed");
            core.failure = Some(error.clone());
            core.parser.output_mut().done = true;

            self.http.cancel();
        }
        result
    }

    /// Stops network work and prevents further event delivery. Safe to repeat.
    pub fn cancel(&self) {
        if !self.cancelled.swap(true, Ordering::AcqRel) {
            self.http.cancel();
            self.diagnostics.finish("cancelled");
        }
    }
}

impl<P: EventParser> Drop for InferenceStream<P> {
    fn drop(&mut self) {
        self.cancel();
    }
}
