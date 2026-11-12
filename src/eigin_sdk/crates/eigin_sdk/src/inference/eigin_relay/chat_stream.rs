use super::EiginRelayWalletSource;
use crate::{http::HttpTransport, inference::*};
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicBool, Ordering},
};

struct StreamState {
    attempted: Vec<String>,
    opened: bool,
    failure: Option<InferenceError>,
}

/// Pull-based relay stream. Only initial HTTP 402 responses permit wallet failover.
#[derive(uniffi::Object)]
pub struct EiginRelayStream {
    config: InferenceProviderConfig,
    wallets: Arc<dyn EiginRelayWalletSource>,
    transport: Arc<dyn HttpTransport>,
    input: InferenceCompletionInput,
    state: Mutex<Option<StreamState>>,
    active: Mutex<Option<Arc<OpenAiCompatibleStream>>>,
    cancelled: AtomicBool,
}

impl EiginRelayStream {
    pub(super) fn new(
        config: InferenceProviderConfig,
        wallets: Arc<dyn EiginRelayWalletSource>,
        transport: Arc<dyn HttpTransport>,
        input: InferenceCompletionInput,
    ) -> Arc<Self> {
        Arc::new(Self {
            config,
            wallets,
            transport,
            input,
            state: Mutex::new(Some(StreamState {
                attempted: vec![],
                opened: false,
                failure: None,
            })),
            active: Mutex::new(None),
            cancelled: AtomicBool::new(false),
        })
    }

    fn check_cancelled(&self) -> Result<(), InferenceError> {
        if self.cancelled.load(Ordering::Acquire) {
            Err(InferenceError::Cancelled)
        } else {
            Ok(())
        }
    }

    fn lease(&self) -> Result<StreamAccess<'_>, InferenceError> {
        self.check_cancelled()?;
        let state = self
            .state
            .lock()
            .unwrap()
            .take()
            .ok_or(InferenceError::Busy)?;
        Ok(StreamAccess {
            owner: self,
            state: Some(state),
            completed: false,
        })
    }

    async fn ensure_open(&self, state: &mut StreamState) -> Result<(), InferenceError> {
        if let Some(error) = &state.failure {
            return Err(error.clone());
        }
        if state.opened {
            return Ok(());
        }
        loop {
            self.check_cancelled()?;
            let token = self
                .wallets
                .next_token(state.attempted.clone())
                .map_err(|_| InferenceError::WalletUnavailable)?;
            self.check_cancelled()?;
            let token = token.ok_or(InferenceError::NoCredits)?;
            if token.is_empty() || state.attempted.contains(&token) {
                return Err(InferenceError::WalletUnavailable);
            }
            state.attempted.push(token.clone());
            let mut config = self.config.clone();
            config.api_token = token.clone();
            let stream =
                OpenAiCompatibleProvider::with_shared_transport(config, self.transport.clone())
                    .stream(self.input.clone())?;
            *self.active.lock().unwrap() = Some(stream.clone());
            self.check_cancelled()?;
            let result = stream.open().await;
            self.check_cancelled()?;
            match result {
                Ok(()) => {
                    state.opened = true;
                    return Ok(());
                }
                Err(InferenceError::Http { status: 402, .. }) => {
                    stream.cancel();
                    self.wallets
                        .mark_exhausted(token)
                        .map_err(|_| InferenceError::WalletUnavailable)?;
                }
                Err(error) => return Err(error),
            }
        }
    }
}

#[uniffi::export]
impl EiginRelayStream {
    /// Validates the initial response, trying another wallet only after HTTP 402.
    pub async fn open(&self) -> Result<(), InferenceError> {
        let mut lease = self.lease()?;
        let result = self.ensure_open(lease.state.as_mut().unwrap()).await;
        lease.finish(&result);
        result
    }

    /// Opens lazily, then delegates event delivery without further wallet attempts.
    pub async fn next(&self) -> Result<Option<InferenceEvent>, InferenceError> {
        let mut lease = self.lease()?;
        let result = async {
            if lease.state.as_ref().unwrap().failure.is_some() {
                return Ok(None);
            }
            self.ensure_open(lease.state.as_mut().unwrap()).await?;
            let stream = self.active.lock().unwrap().clone().unwrap();
            stream.next().await
        }
        .await;
        lease.finish(&result);
        result
    }

    /// Stops the active attempt and prevents further selection or event delivery.
    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::Release);
        if let Some(stream) = self.active.lock().unwrap().as_ref() {
            stream.cancel();
        }
    }
}

impl Drop for EiginRelayStream {
    fn drop(&mut self) {
        self.cancel();
    }
}

struct StreamAccess<'a> {
    owner: &'a EiginRelayStream,
    state: Option<StreamState>,
    completed: bool,
}

impl StreamAccess<'_> {
    fn finish<T>(&mut self, result: &Result<T, InferenceError>) {
        self.completed = true;
        if let Err(error) = result {
            self.state.as_mut().unwrap().failure = Some(error.clone());
            if let Some(stream) = self.owner.active.lock().unwrap().as_ref() {
                stream.cancel();
            }
        }
    }
}

impl Drop for StreamAccess<'_> {
    fn drop(&mut self) {
        *self.owner.state.lock().unwrap() = self.state.take();
        if !self.completed {
            self.owner.cancel();
        }
    }
}
