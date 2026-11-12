use super::*;
use crate::{http::*, inference::*};
use futures::{FutureExt, executor::block_on};
use std::{
    collections::{HashMap, VecDeque},
    sync::{Arc, Mutex},
};

#[derive(Clone, Default)]
struct Wallets {
    tokens: Arc<Mutex<Vec<String>>>,
    exhausted: Arc<Mutex<Vec<String>>>,
    repeated: bool,
    unavailable: bool,
    reject_update: bool,
    selected: Option<Arc<dyn Fn() + Send + Sync>>,
    rejected: Option<Arc<dyn Fn() + Send + Sync>>,
}
impl EiginRelayWalletSource for Wallets {
    fn next_token(&self, excluded: Vec<String>) -> Result<Option<String>, EiginRelayWalletError> {
        if let Some(selected) = &self.selected {
            selected();
        }
        if self.unavailable {
            return Err(EiginRelayWalletError::Unavailable);
        }
        Ok(self
            .tokens
            .lock()
            .unwrap()
            .iter()
            .find(|t| self.repeated || !excluded.contains(t))
            .cloned())
    }
    fn mark_exhausted(&self, token: String) -> Result<(), EiginRelayWalletError> {
        if self.reject_update {
            return Err(EiginRelayWalletError::Unavailable);
        }
        self.exhausted.lock().unwrap().push(token);
        if let Some(rejected) = &self.rejected {
            rejected();
        }
        Ok(())
    }
}

type Reply = (u16, Vec<u8>);

#[derive(Clone, Default)]
struct Transport {
    replies: Arc<Mutex<VecDeque<Reply>>>,
    bodies: Arc<Mutex<HashMap<u64, Vec<u8>>>>,
    requests: Arc<Mutex<Vec<HttpRequest>>>,
    closed: Arc<Mutex<Vec<u64>>>,
    pending: Arc<Mutex<Option<Arc<HttpResponseHeadCallback>>>>,
    hold: bool,
    hold_body: bool,
    pending_body: Arc<Mutex<Option<Arc<HttpBodyChunkCallback>>>>,
}
impl HttpTransport for Transport {
    fn start_request(
        &self,
        id: u64,
        request: HttpRequest,
        callback: Arc<HttpResponseHeadCallback>,
    ) {
        self.requests.lock().unwrap().push(request);
        if self.hold {
            *self.pending.lock().unwrap() = Some(callback);
            return;
        }
        let (status, body) = self
            .replies
            .lock()
            .unwrap()
            .pop_front()
            .expect("unexpected request");
        self.bodies.lock().unwrap().insert(id, body);
        callback.succeed(HttpResponseHead {
            status,
            headers: Default::default(),
        });
    }
    fn read(&self, id: u64, callback: Arc<HttpBodyChunkCallback>) {
        if self.hold_body {
            *self.pending_body.lock().unwrap() = Some(callback);
            return;
        }
        callback.succeed(self.bodies.lock().unwrap().remove(&id));
    }
    fn close(&self, id: u64) {
        self.closed.lock().unwrap().push(id);
    }
}
fn setup(statuses: &[u16]) -> (Arc<EiginRelayProvider>, Wallets, Transport) {
    let wallets = Wallets {
        tokens: Arc::new(Mutex::new(vec!["first".into(), "second".into()])),
        ..Default::default()
    };
    let transport = Transport::default();
    for status in statuses {
        transport.replies.lock().unwrap().push_back((*status, if *status == 200 {
            b"data: {\"choices\":[{\"delta\":{\"content\":\"hello\"},\"finish_reason\":\"stop\"}]}\n\n".to_vec()
        } else { b"failure".to_vec() }));
    }
    let provider = make_provider(wallets.clone(), transport.clone());
    (provider, wallets, transport)
}
fn make_provider(wallets: Wallets, transport: Transport) -> Arc<EiginRelayProvider> {
    EiginRelayProvider::with_transport(
        EiginRelayProviderConfig {
            base_url: "https://relay.test/".into(),
            relay_key: "relay-key".into(),
        },
        Box::new(wallets),
        Box::new(transport),
    )
    .unwrap()
}
fn input() -> InferenceCompletionInput {
    InferenceCompletionInput {
        model: "test-model".into(),
        reasoning_effort: Some("none".into()),
        ..Default::default()
    }
}

mod cancellation;
mod requests;
