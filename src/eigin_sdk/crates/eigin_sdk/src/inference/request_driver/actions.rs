use super::*;

impl InferenceRequest {
    pub(super) fn perform(
        &mut self,
        actions: Vec<Action>,
        source: u64,
        mut event: Option<InferenceEvent>,
    ) {
        for action in actions {
            match action {
                Action::Open { id } => {
                    let effects = self.effects.clone();
                    let model = self.models[&id].clone();
                    let cancellation = self.cancellation.clone();
                    self.spawn(id, async move {
                        let result = work::open(effects.as_ref(), &cancellation, id, model.clone())
                            .await
                            .map(Some);
                        Work::Opened { id, model, result }
                    });
                }
                Action::CancelOpening { id } => self.abort(id),
                Action::Forward { id } => {
                    if id == 1 {
                        self.hedge_opened = Some(self.clock.now());
                    }
                    self.buffers.insert(id, vec![]);
                    self.read(id);
                }
                Action::RecordOpenFailure { id } => {
                    let effects = self.effects.clone();
                    let model = self.models[&id].clone();
                    let error = self.errors[&id].clone();
                    effects.record_failure(model, error);
                }
                Action::Buffer => self
                    .buffers
                    .entry(source)
                    .or_default()
                    .push(event.take().unwrap()),
                Action::Overflow => {
                    self.abort(source);
                    self.errors.insert(source, RequestError::BufferOverflow);
                    self.observe(Observation::Ended { id: source }, source, None);
                }
                Action::Win { id } => self.policy.selected(self.models[&id].clone()),
                Action::Lose { id } => {
                    let since = if id == 1 {
                        self.hedge_opened.unwrap_or(self.started)
                    } else {
                        self.started
                    };
                    let silent_ms = self
                        .clock
                        .now()
                        .saturating_sub(since)
                        .as_millis()
                        .min(u64::MAX as u128) as u64;
                    let model = self.models[&id].clone();
                    let ids: Vec<_> = self
                        .aborts
                        .keys()
                        .copied()
                        .filter(|key| if id == 1 { *key == 1 } else { *key != 1 })
                        .collect();
                    for key in ids {
                        self.abort(key);
                    }
                    self.buffers.remove(&id);
                    self.effects.record_loser(model, silent_ms);
                }
                Action::Deliver => {
                    self.output
                        .extend(self.buffers.remove(&source).unwrap_or_default());
                    self.output.push_back(event.take().unwrap());
                }
                Action::Chase {
                    failed,
                    replacement,
                    timeout,
                } => {
                    self.abort(failed);
                    self.buffers.remove(&failed);
                    let error = if timeout {
                        RequestError::FirstEventTimeout
                    } else {
                        self.errors
                            .get(&failed)
                            .cloned()
                            .unwrap_or(RequestError::NoUsefulOutput)
                    };
                    let model = self.models[&failed].clone();
                    self.models.insert(replacement, model.clone());
                    self.errors.insert(replacement, error.clone());
                    self.spawn(
                        replacement,
                        work::replacement(
                            self.effects.clone(),
                            self.policy.clone(),
                            self.cancellation.clone(),
                            replacement,
                            model,
                            error,
                        ),
                    );
                }
                Action::Finish {
                    error_source,
                    timeout,
                } => {
                    self.finished = Some(if timeout {
                        Some(RequestError::FirstEventTimeout)
                    } else {
                        self.errors.get(&error_source).cloned()
                    });
                    self.stop_tasks();
                }
            }
        }
    }

    pub(super) fn abort(&mut self, id: u64) {
        let cancelled_hedge_open =
            id == 1 && self.aborts.contains_key(&id) && !self.streams.contains_key(&id);
        self.cancellation.remove(id);
        if let Some(abort) = self.aborts.remove(&id) {
            abort.abort();
            self.effects.cancel(id);
        }
        if let Some(stream) = self.streams.remove(&id) {
            stream.0.cancel();
        }
        // Preserve cancellation reporting for an opening hedge (#446).
        if cancelled_hedge_open {
            self.errors.insert(id, InferenceError::Cancelled.into());
            self.observe(Observation::OpenFailed { id }, id, None);
        }
    }

    pub(super) fn stop_tasks(&mut self) {
        self.effects.close();
        let ids: Vec<_> = self.aborts.keys().copied().collect();
        for id in ids {
            self.abort(id);
        }
        self.tasks.clear();
    }
}
