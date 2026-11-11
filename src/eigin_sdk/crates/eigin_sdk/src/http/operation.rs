use super::*;
use std::sync::Arc;
use std::sync::{
    Mutex,
    atomic::{AtomicU64, Ordering},
};

static NEXT_ID: AtomicU64 = AtomicU64::new(1);

enum Pending {
    Head(Arc<HttpResponseHeadCallback>),
    Body(Arc<HttpBodyChunkCallback>),
}

impl Pending {
    fn cancel(&self) {
        match self {
            Self::Head(c) => c.0.complete(Err(HttpTransportError::Cancelled)),
            Self::Body(c) => c.0.complete(Err(HttpTransportError::Cancelled)),
        }
    }
}

#[derive(Default)]
struct State {
    opened: bool,
    eof: bool,
    closed: bool,
    dispatching: bool,
    pending: Option<Pending>,
}

/// A single HTTP exchange. Cancellation also wakes pending foreign futures.
#[derive(uniffi::Object)]
pub struct HttpOperation {
    id: u64,
    transport: Arc<dyn HttpTransport>,
    state: Mutex<State>,
}

impl HttpOperation {
    /// Creates an independent exchange sharing a Rust transport instance.
    pub fn with_transport(transport: Arc<dyn HttpTransport>) -> Arc<Self> {
        Arc::new(Self {
            id: NEXT_ID.fetch_add(1, Ordering::Relaxed),
            transport,
            state: Mutex::new(State::default()),
        })
    }

    fn dispatch(
        &self,
        pending: Pending,
        opening: bool,
        call: impl FnOnce(),
    ) -> Result<(), HttpTransportError> {
        {
            let mut state = self.state.lock().unwrap();
            if state.closed {
                return Err(HttpTransportError::Cancelled);
            }
            if state.pending.is_some() || (opening && state.opened) || (!opening && !state.opened) {
                return Err(HttpTransportError::Busy);
            }
            if opening {
                state.opened = true;
            }
            state.pending = Some(pending);
            state.dispatching = true;
        }
        call();
        let closed = {
            let mut state = self.state.lock().unwrap();
            state.dispatching = false;
            state.closed
        };
        // Cancellation racing with dispatch closes after the host registered the ID.
        if closed {
            self.transport.close(self.id);
        }
        Ok(())
    }
}

#[uniffi::export]
impl HttpOperation {
    /// Creates an exchange using an explicitly supplied platform transport.
    #[uniffi::constructor]
    pub fn new(transport: Box<dyn HttpTransport>) -> Arc<Self> {
        Self::with_transport(transport.into())
    }

    /// Sends once and waits for status/headers. Concurrent calls return Busy.
    pub async fn send(&self, request: HttpRequest) -> Result<HttpResponseHead, HttpTransportError> {
        let completion = Arc::new(HttpResponseHeadCallback::default());
        self.dispatch(Pending::Head(completion.clone()), true, || {
            self.transport
                .start_request(self.id, request, completion.clone())
        })?;
        let mut guard = PendingGuard {
            operation: self,
            completed: false,
        };
        let result = completion.0.wait().await;
        guard.completed = result.is_ok();
        if self.state.lock().unwrap().closed {
            return Err(HttpTransportError::Cancelled);
        }
        result
    }

    /// Reads one chunk and releases the exchange at EOF. Repeated EOF reads are safe.
    pub async fn read(&self) -> Result<Option<Vec<u8>>, HttpTransportError> {
        if self.state.lock().unwrap().eof {
            return Ok(None);
        }
        let completion = Arc::new(HttpBodyChunkCallback::default());
        self.dispatch(Pending::Body(completion.clone()), false, || {
            self.transport.read(self.id, completion.clone())
        })?;
        let mut guard = PendingGuard {
            operation: self,
            completed: false,
        };
        let result = completion.0.wait().await;
        guard.completed = result.is_ok();
        if self.state.lock().unwrap().closed {
            return Err(HttpTransportError::Cancelled);
        }
        if matches!(result, Ok(None)) {
            self.state.lock().unwrap().eof = true;
            self.cancel();
        }
        result
    }

    /// Closes the response and aborts any pending request/read. Safe to repeat.
    pub fn cancel(&self) {
        let (pending, close) = {
            let mut state = self.state.lock().unwrap();
            if state.closed {
                return;
            }
            state.closed = true;
            (state.pending.take(), !state.dispatching)
        };
        if let Some(pending) = pending {
            pending.cancel();
        }
        if close {
            self.transport.close(self.id);
        }
    }
}

impl Drop for HttpOperation {
    fn drop(&mut self) {
        self.cancel();
    }
}

struct PendingGuard<'a> {
    operation: &'a HttpOperation,
    completed: bool,
}

impl Drop for PendingGuard<'_> {
    fn drop(&mut self) {
        self.operation.state.lock().unwrap().pending = None;
        if !self.completed {
            self.operation.cancel();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use futures::executor::block_on;
    use std::sync::atomic::AtomicUsize;

    struct EmptyBody(Arc<AtomicUsize>);
    impl HttpTransport for EmptyBody {
        fn start_request(&self, _: u64, _: HttpRequest, completion: Arc<HttpResponseHeadCallback>) {
            completion.succeed(HttpResponseHead {
                status: 200,
                headers: Default::default(),
            });
        }
        fn read(&self, _: u64, completion: Arc<HttpBodyChunkCallback>) {
            completion.succeed(None);
        }
        fn close(&self, _: u64) {
            self.0.fetch_add(1, Ordering::SeqCst);
        }
    }

    #[test]
    fn eof_closes_exchange_even_when_operation_is_retained() {
        let closes = Arc::new(AtomicUsize::new(0));
        let operation = HttpOperation::new(Box::new(EmptyBody(closes.clone())));
        block_on(operation.send(HttpRequest {
            url: "https://example.test".into(),
            method: "GET".into(),
            headers: Default::default(),
            body: vec![],
        }))
        .unwrap();
        assert!(block_on(operation.read()).unwrap().is_none());
        assert_eq!(closes.load(Ordering::SeqCst), 1);
        assert!(block_on(operation.read()).unwrap().is_none());
        operation.cancel();
        drop(operation);
        assert_eq!(closes.load(Ordering::SeqCst), 1);
    }

    struct DelayedHead {
        head: Arc<Mutex<Option<Arc<HttpResponseHeadCallback>>>>,
        closes: Arc<AtomicUsize>,
    }
    impl HttpTransport for DelayedHead {
        fn start_request(&self, _: u64, _: HttpRequest, completion: Arc<HttpResponseHeadCallback>) {
            *self.head.lock().unwrap() = Some(completion);
        }
        fn read(&self, _: u64, _: Arc<HttpBodyChunkCallback>) {
            panic!("overlapping read dispatched");
        }
        fn close(&self, _: u64) {
            self.closes.fetch_add(1, Ordering::SeqCst);
        }
    }

    #[test]
    fn cancellation_and_dropped_futures_close_pending_work_and_ignore_late_completion() {
        use futures::FutureExt;
        for drop_pending in [false, true] {
            let head = Arc::new(Mutex::new(None));
            let closes = Arc::new(AtomicUsize::new(0));
            let operation = HttpOperation::new(Box::new(DelayedHead {
                head: head.clone(),
                closes: closes.clone(),
            }));
            let mut send = Box::pin(operation.send(HttpRequest {
                url: "https://example.test".into(),
                method: "GET".into(),
                headers: Default::default(),
                body: vec![],
            }));
            assert!(send.as_mut().now_or_never().is_none());
            assert!(matches!(
                block_on(operation.read()),
                Err(HttpTransportError::Busy)
            ));
            if drop_pending {
                drop(send);
            } else {
                operation.cancel();
                assert!(matches!(block_on(send), Err(HttpTransportError::Cancelled)));
            }
            head.lock()
                .unwrap()
                .take()
                .unwrap()
                .succeed(HttpResponseHead {
                    status: 200,
                    headers: Default::default(),
                });
            assert!(matches!(
                block_on(operation.read()),
                Err(HttpTransportError::Cancelled)
            ));
            operation.cancel();
            drop(operation);
            assert_eq!(closes.load(Ordering::SeqCst), 1);
        }
    }
}
