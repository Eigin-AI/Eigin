use super::{RequestCancellation, RequestCandidate, RequestEffects, RequestError};
use crate::inference::InferenceAttempts;
use std::sync::Arc;

pub(super) struct Candidate(pub Arc<dyn RequestCandidate>);
impl Drop for Candidate {
    fn drop(&mut self) {
        self.0.cancel();
    }
}

pub(super) enum Work {
    Opened {
        id: u64,
        model: String,
        result: Result<Option<Arc<Candidate>>, RequestError>,
    },
    Read {
        id: u64,
        result: Result<Option<crate::inference::InferenceEvent>, RequestError>,
    },
}

pub(super) async fn open(
    effects: &dyn RequestEffects,
    cancellation: &RequestCancellation,
    id: u64,
    model: String,
) -> Result<Arc<Candidate>, RequestError> {
    cancellation.check()?;
    let prepared = effects.prepare(id, model.clone()).await;
    cancellation.check()?;
    let effort = prepared?;
    let stream = effects
        .open(id, model, effort)
        .await
        .map(|stream| Arc::new(Candidate(stream)));
    cancellation.check()?;
    stream
}

pub(super) async fn replacement(
    effects: Arc<dyn RequestEffects>,
    policy: Arc<InferenceAttempts>,
    cancellation: Arc<RequestCancellation>,
    id: u64,
    model: String,
    error: RequestError,
) -> Work {
    while !cancellation.is_cancelled() {
        let work = policy.replacement_work(model.clone(), error.missing_model(), error.cancelled());
        let Some(failed_model) = work.record_model else {
            break;
        };
        effects.record_failure(failed_model, error.clone());
        if cancellation.is_cancelled() {
            break;
        }
        if work.refresh {
            effects.refresh_catalog().await;
        }
        if cancellation.is_cancelled() {
            break;
        }
        if !work.rank {
            policy.exhausted();
            break;
        }
        let next = effects.rank_replacement(model.clone(), error.clone()).await;
        if cancellation.is_cancelled() {
            break;
        }
        let Some(next) = next else {
            policy.exhausted();
            break;
        };
        // A failed preparation still spends a switch; a stale grant masks that failure.
        let prepared = effects.prepare(id, next.clone()).await;
        if cancellation.is_cancelled() {
            break;
        }
        if !policy.claim_switch(id, model.clone(), next.clone()) {
            policy.exhausted();
            break;
        }
        let opened = match prepared {
            Ok(effort) => effects
                .open(id, next.clone(), effort)
                .await
                .map(|stream| Arc::new(Candidate(stream))),
            Err(error) => Err(error),
        };
        if cancellation.is_cancelled() {
            break;
        }
        match opened {
            Ok(stream) => {
                policy.replacement_opened(next.clone());
                return Work::Opened {
                    id,
                    model: next,
                    result: Ok(Some(stream)),
                };
            }
            Err(error) if error.cancelled() => break,
            // Preserve the original chase's failure and model attribution (#442).
            Err(_) => {}
        }
    }
    Work::Opened {
        id,
        model,
        result: Ok(None),
    }
}
