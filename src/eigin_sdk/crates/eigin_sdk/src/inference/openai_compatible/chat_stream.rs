use super::inference_diagnostics::InferenceDiagnostics;
use super::{adapters::Adapter, stream::StreamParser, types::*};
use crate::http::*;
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicBool, Ordering},
};

struct StreamState {
    request: Option<HttpRequest>,
    parser: StreamParser,
    buffer: Vec<u8>,
    skip_lf: bool,
    opened: bool,
    failure: Option<InferenceError>,
    first_event: bool,
}

/// Cancellable, pull-based provider stream. Only one open/next may be pending.
#[derive(uniffi::Object)]
pub struct OpenAiCompatibleStream {
    http: Arc<HttpOperation>,
    core: Mutex<Option<StreamState>>,
    cancelled: AtomicBool,
    diagnostics: InferenceDiagnostics,
    model: String,
}

impl OpenAiCompatibleStream {
    pub(super) fn new(
        http: Arc<HttpOperation>,
        request: HttpRequest,
        adapter: Adapter,
        input: InferenceCompletionInput,
    ) -> Arc<Self> {
        Arc::new(Self {
            http,
            core: Mutex::new(Some(StreamState {
                request: Some(request),
                parser: StreamParser::new(adapter, &input),
                buffer: vec![],
                skip_lf: false,
                opened: false,
                failure: None,
                first_event: true,
            })),
            cancelled: AtomicBool::new(false),
            diagnostics: InferenceDiagnostics::new("stream"),
            model: input.model,
        })
    }

    fn lease(&self) -> Result<StreamAccessGuard<'_>, InferenceError> {
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

    async fn ensure_open(&self, core: &mut StreamState) -> Result<(), InferenceError> {
        if let Some(error) = &core.failure {
            return Err(error.clone());
        }
        if core.opened {
            return Ok(());
        }
        self.diagnostics.start(Some(&self.model));
        let request = core.request.take().ok_or(InferenceError::Busy)?;
        let head = self.http.send(request).await?;
        core.opened = true;
        self.diagnostics.headers(head.status);
        if !(200..300).contains(&head.status) {
            let mut bytes = Vec::new();
            while bytes.len() < 2000 {
                let Some(chunk) = self.http.read().await? else {
                    break;
                };
                self.diagnostics.chunk(chunk.len());
                bytes.extend(chunk.into_iter().take(2000 - bytes.len()));
            }
            self.http.cancel();
            return Err(InferenceError::Http {
                status: head.status,
                body: (!bytes.is_empty()).then(|| String::from_utf8_lossy(&bytes).into_owned()),
            });
        }
        Ok(())
    }
}

#[uniffi::export]
impl OpenAiCompatibleStream {
    /// Opens HTTP and validates status without consuming successful response data.
    pub async fn open(&self) -> Result<(), InferenceError> {
        let mut lease = self.lease()?;
        let core = lease.core.as_mut().unwrap();
        let result = self.ensure_open(core).await;
        lease.completed = true;
        if let Err(error) = &result {
            core.failure = Some(error.clone());
            core.parser.done = true;

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
            if core.parser.done && core.parser.events.is_empty() && core.parser.error.is_none() {
                self.diagnostics.finish("request finished");
                return Ok(None);
            }
            self.ensure_open(core).await?;
            loop {
                if self.cancelled.load(Ordering::Acquire) {
                    return Err(InferenceError::Cancelled);
                }
                if let Some(event) = core.parser.events.pop_front() {
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
                if let Some(error) = core.parser.error.take() {
                    core.parser.done = true;
                    return Err(error);
                }
                if core.parser.done {
                    self.diagnostics.finish("request finished");
                    return Ok(None);
                }
                if let Some(line) = take_line(&mut core.buffer, &mut core.skip_lf) {
                    if line.len() > 1024 * 1024 {
                        return Err(InferenceError::LimitExceeded {
                            limit: "1 MiB SSE line".into(),
                        });
                    }
                    core.parser.line(&line);
                    if core.parser.done || core.parser.error.is_some() {
                        self.http.cancel();
                    }
                    continue;
                }
                if core.buffer.len() > 1024 * 1024 {
                    return Err(InferenceError::LimitExceeded {
                        limit: "1 MiB SSE line".into(),
                    });
                }
                match self.http.read().await {
                    Ok(Some(chunk)) => {
                        self.diagnostics.chunk(chunk.len());
                        if chunk.len() > 1024 * 1024 {
                            return Err(InferenceError::LimitExceeded {
                                limit: "1 MiB HTTP chunk".into(),
                            });
                        }
                        core.buffer.extend(chunk);
                    }
                    Ok(None) => {
                        if !core.buffer.is_empty() {
                            core.parser.line(&std::mem::take(&mut core.buffer));
                        }
                        core.parser.eof();

                        self.http.cancel();
                    }
                    Err(error) => {
                        return Err(if core.parser.refused {
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
            core.parser.done = true;

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

impl Drop for OpenAiCompatibleStream {
    fn drop(&mut self) {
        self.cancel();
    }
}

struct StreamAccessGuard<'a> {
    owner: &'a OpenAiCompatibleStream,
    core: Option<StreamState>,
    completed: bool,
}

impl Drop for StreamAccessGuard<'_> {
    fn drop(&mut self) {
        *self.owner.core.lock().unwrap() = self.core.take();
        if !self.completed {
            self.owner.cancel();
        }
    }
}

fn take_line(buffer: &mut Vec<u8>, skip_lf: &mut bool) -> Option<Vec<u8>> {
    if *skip_lf && !buffer.is_empty() {
        if buffer[0] == b'\n' {
            buffer.remove(0);
        }
        *skip_lf = false;
    }
    let end = buffer.iter().position(|b| *b == b'\n' || *b == b'\r')?;
    *skip_lf = buffer[end] == b'\r';
    let mut line: Vec<_> = buffer.drain(..=end).collect();
    line.pop();
    Some(line)
}
