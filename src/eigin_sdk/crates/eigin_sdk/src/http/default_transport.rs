use super::*;
use std::sync::Arc;
use std::{
    collections::HashMap,
    future::Future,
    sync::{Mutex, OnceLock},
    time::Duration,
};
use tokio::{runtime::Runtime, task::AbortHandle};

static HTTP_IO_RUNTIME: OnceLock<Result<Runtime, String>> = OnceLock::new();

fn http_runtime() -> Result<&'static Runtime, HttpTransportError> {
    HTTP_IO_RUNTIME
        .get_or_init(|| {
            tokio::runtime::Builder::new_multi_thread()
                .worker_threads(2)
                .thread_name("eigin-http")
                .enable_all()
                .build()
                .map_err(|e| e.to_string())
        })
        .as_ref()
        .map_err(|reason| HttpTransportError::Failed {
            reason: reason.clone(),
            domain: None,
            code: None,
        })
}

struct Body {
    response: reqwest::Response,
    remaining: Vec<u8>,
}

#[derive(Default)]
struct TaskState {
    cancelled: bool,
    task: Option<AbortHandle>,
}

#[derive(Default)]
struct Exchange {
    task: Mutex<TaskState>,
    body: tokio::sync::Mutex<Option<Body>>,
}

impl Exchange {
    fn spawn(&self, future: impl Future<Output = ()> + Send + 'static) {
        let mut state = self.task.lock().unwrap();
        let handle = http_runtime()
            .expect("runtime initialized by transport constructor")
            .spawn(future)
            .abort_handle();
        if state.cancelled {
            handle.abort();
        } else {
            state.task = Some(handle);
        }
    }

    fn cancel(&self) {
        let mut state = self.task.lock().unwrap();
        state.cancelled = true;
        if let Some(task) = state.task.take() {
            task.abort();
        }
    }
}

/// Default native HTTP. Owns its Tokio I/O runtime; callers may use any executor.
pub struct DefaultHttpTransport {
    client: reqwest::Client,
    exchanges: Mutex<HashMap<u64, Arc<Exchange>>>,
}

impl DefaultHttpTransport {
    /// Uses platform trust, environment proxies and 30s connect/60s read timeouts.
    /// Redirects stay on the original origin; requests are never automatically retried.
    pub fn new() -> Result<Self, HttpTransportError> {
        http_runtime()?;
        let client = reqwest::Client::builder()
            .redirect(reqwest::redirect::Policy::custom(|attempt| {
                if attempt.previous().len() >= 10 {
                    return attempt.error("too many redirects");
                }
                if attempt
                    .previous()
                    .first()
                    .is_some_and(|first| first.origin() != attempt.url().origin())
                {
                    return attempt.stop();
                }
                attempt.follow()
            }))
            .connect_timeout(Duration::from_secs(30))
            .read_timeout(Duration::from_secs(60))
            .retry(reqwest::retry::never())
            .build()
            .map_err(|e| HttpTransportError::Failed {
                reason: e.without_url().to_string(),
                domain: None,
                code: None,
            })?;
        Ok(Self {
            client,
            exchanges: Mutex::new(HashMap::new()),
        })
    }
}

impl HttpTransport for DefaultHttpTransport {
    fn start_request(
        &self,
        id: u64,
        request: HttpRequest,
        completion: Arc<HttpResponseHeadCallback>,
    ) {
        let exchange = Arc::new(Exchange::default());
        self.exchanges.lock().unwrap().insert(id, exchange.clone());
        let client = self.client.clone();
        let task_exchange = exchange.clone();
        exchange.spawn(async move {
            let method = match reqwest::Method::from_bytes(request.method.as_bytes()) {
                Ok(method) => method,
                Err(error) => {
                    completion.fail(error.to_string());
                    return;
                }
            };
            let mut builder = client.request(method, request.url);
            if !request.body.is_empty() {
                builder = builder.body(request.body);
            }
            for (key, value) in request.headers {
                builder = builder.header(key, value);
            }
            match builder.send().await {
                Ok(response) => {
                    let head = HttpResponseHead {
                        status: response.status().as_u16(),
                        headers: response
                            .headers()
                            .iter()
                            .filter_map(|(k, v)| {
                                v.to_str().ok().map(|v| (k.to_string(), v.to_string()))
                            })
                            .collect(),
                    };
                    *task_exchange.body.lock().await = Some(Body {
                        response,
                        remaining: Vec::new(),
                    });
                    completion.succeed(head);
                }
                Err(error) => completion.fail(error.without_url().to_string()),
            }
        });
    }

    fn read(&self, id: u64, completion: Arc<HttpBodyChunkCallback>) {
        let exchange = self.exchanges.lock().unwrap().get(&id).cloned();
        let Some(exchange) = exchange else {
            completion.fail("response closed".into());
            return;
        };
        let task_exchange = exchange.clone();
        exchange.spawn(async move {
            let mut body = task_exchange.body.lock().await;
            let Some(body) = body.as_mut() else {
                completion.fail("response unavailable".into());
                return;
            };
            if body.remaining.is_empty() {
                match body.response.chunk().await {
                    Ok(Some(bytes)) => {
                        if bytes.len() > 1024 * 1024 {
                            completion.fail("HTTP chunk exceeds 1 MiB".into());
                            return;
                        }
                        body.remaining = bytes.to_vec();
                    }
                    Ok(None) => {
                        completion.succeed(None);
                        return;
                    }
                    Err(error) => {
                        completion.fail(error.without_url().to_string());
                        return;
                    }
                }
            }
            let remaining = body
                .remaining
                .split_off(body.remaining.len().min(64 * 1024));
            completion.succeed(Some(std::mem::replace(&mut body.remaining, remaining)));
        });
    }

    fn close(&self, id: u64) {
        let exchange = self.exchanges.lock().unwrap().remove(&id);
        if let Some(exchange) = exchange {
            exchange.cancel();
        }
    }
}
