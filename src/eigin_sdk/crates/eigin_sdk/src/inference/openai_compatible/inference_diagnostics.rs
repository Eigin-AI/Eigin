use crate::{DiagnosticContext, DiagnosticLevel, DiagnosticPrivacy, diagnostics::delivery::emit};
use std::sync::{
    Mutex,
    atomic::{AtomicBool, AtomicU16, AtomicU64, Ordering},
};
use web_time::Instant;

static NEXT_OPERATION: AtomicU64 = AtomicU64::new(1);

/// Per-request observations shared by streaming and one-shot provider operations.
pub(super) struct InferenceDiagnostics {
    context: DiagnosticContext,
    kind: &'static str,
    started: Mutex<Option<Instant>>,
    finished: AtomicBool,
    status: AtomicU16,
    bytes: AtomicU64,
    chunks: AtomicU64,
    events: AtomicU64,
}

impl InferenceDiagnostics {
    pub fn new(kind: &'static str) -> Self {
        Self {
            context: DiagnosticContext {
                operation_id: format!(
                    "inference-{}",
                    NEXT_OPERATION.fetch_add(1, Ordering::Relaxed)
                ),
                parent_operation_id: None,
            },
            kind,
            started: Mutex::new(None),
            finished: AtomicBool::new(false),
            status: AtomicU16::new(0),
            bytes: AtomicU64::new(0),
            chunks: AtomicU64::new(0),
            events: AtomicU64::new(0),
        }
    }

    pub fn start(&self, model: Option<&str>) {
        *self.started.lock().unwrap() = Some(Instant::now());
        self.record("request started", model, None);
    }

    pub fn headers(&self, status: u16) {
        self.status.store(status, Ordering::Relaxed);
        self.record("response headers", None, None);
    }

    pub fn chunk(&self, bytes: usize) {
        self.bytes.fetch_add(bytes as u64, Ordering::Relaxed);
        self.chunks.fetch_add(1, Ordering::Relaxed);
    }

    pub fn event(&self) {
        self.events.fetch_add(1, Ordering::Relaxed);
    }

    pub fn finish(&self, outcome: &'static str) {
        if !self.finished.swap(true, Ordering::AcqRel) {
            self.record(outcome, None, None);
        }
    }

    pub fn record(&self, message: &'static str, model: Option<&str>, excerpt: Option<&str>) {
        emit(
            DiagnosticLevel::Debug,
            "inference.openai-compatible",
            message,
            |event| {
                event.field("operation", DiagnosticPrivacy::Public, || self.kind.into());
                event.field("elapsed_ms", DiagnosticPrivacy::Public, || {
                    self.started
                        .lock()
                        .unwrap()
                        .map(|start| start.elapsed().as_millis())
                        .unwrap_or(0)
                        .to_string()
                });
                for (name, value) in [
                    ("bytes_received", self.bytes.load(Ordering::Relaxed)),
                    ("chunks_received", self.chunks.load(Ordering::Relaxed)),
                    ("events_delivered", self.events.load(Ordering::Relaxed)),
                ] {
                    event.field(name, DiagnosticPrivacy::Public, || value.to_string());
                }
                let status = self.status.load(Ordering::Relaxed);
                if status != 0 {
                    event.field("status", DiagnosticPrivacy::Public, || status.to_string());
                }
                if let Some(model) = model {
                    event.field("model", DiagnosticPrivacy::Private, || model.into());
                }
                if let Some(excerpt) = excerpt {
                    event.field("excerpt", DiagnosticPrivacy::Private, || {
                        excerpt.chars().take(256).collect()
                    });
                }
                Some(self.context.clone())
            },
        );
    }
}
