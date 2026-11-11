use super::{inference_diagnostics::InferenceDiagnostics, request::request, types::*};
use crate::http::*;
use std::{
    future::Future,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
};

const MAX_RESPONSE_BYTES: usize = 4 * 1024 * 1024;

pub(super) struct ProviderRequest {
    config: InferenceProviderConfig,
    http: Arc<HttpOperation>,
    started: AtomicBool,
    cancelled: AtomicBool,
    diagnostics: InferenceDiagnostics,
}

impl ProviderRequest {
    pub fn new(
        config: InferenceProviderConfig,
        transport: Arc<dyn HttpTransport>,
        kind: &'static str,
    ) -> Self {
        Self {
            config,
            http: HttpOperation::with_transport(transport),
            started: AtomicBool::new(false),
            cancelled: AtomicBool::new(false),
            diagnostics: InferenceDiagnostics::new(kind),
        }
    }

    pub async fn run<T>(
        &self,
        model: Option<&str>,
        work: impl Future<Output = Result<T, InferenceError>>,
    ) -> Result<T, InferenceError> {
        if self.started.swap(true, Ordering::AcqRel) {
            return Err(InferenceError::Busy);
        }
        if self.cancelled.load(Ordering::Acquire) {
            return Err(InferenceError::Cancelled);
        }
        let _cancel_on_drop = CancelRequestOnDrop(self);
        self.diagnostics.start(model);
        let result = work.await;
        self.diagnostics.finish(if result.is_ok() {
            "request finished"
        } else {
            "request failed"
        });
        result
    }

    pub async fn send(
        &self,
        path: &str,
        body: Option<Vec<u8>>,
    ) -> Result<HttpResponseHead, InferenceError> {
        let head = self.http.send(request(&self.config, path, body)?).await?;
        self.diagnostics.headers(head.status);
        Ok(head)
    }

    pub async fn read_body(&self) -> Result<Vec<u8>, InferenceError> {
        let mut bytes = Vec::new();
        while let Some(chunk) = self.http.read().await? {
            self.diagnostics.chunk(chunk.len());
            if bytes.len() + chunk.len() > MAX_RESPONSE_BYTES {
                return Err(InferenceError::LimitExceeded {
                    limit: format!("{MAX_RESPONSE_BYTES} body bytes"),
                });
            }
            bytes.extend(chunk);
        }
        Ok(bytes)
    }

    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::Release);
        self.http.cancel();
        self.diagnostics.finish("cancelled");
    }
}

// Cancels the exchange when its future completes or is abandoned by a host.
struct CancelRequestOnDrop<'a>(&'a ProviderRequest);

impl Drop for CancelRequestOnDrop<'_> {
    fn drop(&mut self) {
        self.0.cancel();
    }
}
