//! Per-call authorization and execution deadlines. The host executes the tool.
use crate::clock::{now, sleep_until};
use futures_channel::oneshot;
use futures_util::future::{Either, FutureExt, Shared, select};
use std::{sync::Mutex, time::Duration};

const TIMEOUT_MS: u32 = 30_000;

/// Effective permission for this call after applying the host's stored grants.
#[derive(uniffi::Enum)]
pub enum CallPermission {
    Always,
    Ask,
    Never,
}

/// A host prompt's response, scoped to this call or the current chat.
#[derive(uniffi::Enum)]
pub enum CallGrant {
    Once,
    ForChat,
    Deny,
}

/// Scope to apply before dispatching a newly approved call.
#[derive(Debug, PartialEq, uniffi::Enum)]
pub enum CallGrantScope {
    Once,
    ForChat,
}

/// The host maps each refusal to its existing error payload.
#[derive(Debug, PartialEq, uniffi::Enum)]
pub enum CallDenial {
    Policy,
    PromptUnavailable,
    User,
}

/// Next host operation for this call.
#[derive(Debug, PartialEq, uniffi::Enum)]
pub enum ToolCallAction {
    Prompt,
    Denied {
        reason: CallDenial,
    },
    Interactive,
    Timed {
        timeout_ms: u32,
        grant: Option<CallGrantScope>,
    },
}

/// Authorizes execution without starting a clock while permission is pending.
#[uniffi::export]
pub fn agent_authorize_call(
    permission: CallPermission,
    can_prompt: bool,
    interactive: bool,
) -> ToolCallAction {
    match permission {
        CallPermission::Never => ToolCallAction::Denied {
            reason: CallDenial::Policy,
        },
        CallPermission::Ask if !can_prompt => ToolCallAction::Denied {
            reason: CallDenial::PromptUnavailable,
        },
        CallPermission::Ask => ToolCallAction::Prompt,
        CallPermission::Always if interactive => ToolCallAction::Interactive,
        CallPermission::Always => timed(None),
    }
}

/// Approvals following a prompt are timed, including interactive tools.
#[uniffi::export]
pub fn agent_resolve_call_prompt(response: CallGrant) -> ToolCallAction {
    match response {
        CallGrant::Once => timed(Some(CallGrantScope::Once)),
        CallGrant::ForChat => timed(Some(CallGrantScope::ForChat)),
        CallGrant::Deny => ToolCallAction::Denied {
            reason: CallDenial::User,
        },
    }
}

fn timed(grant: Option<CallGrantScope>) -> ToolCallAction {
    ToolCallAction::Timed {
        timeout_ms: TIMEOUT_MS,
        grant,
    }
}

/// A monotonic deadline starting at dispatch. Host values stay in the host task.
#[derive(uniffi::Object)]
pub struct ToolCallDeadline {
    expires: Duration,
    clock: fn() -> Duration,
    sender: Mutex<Option<oneshot::Sender<bool>>>,
    finished: Shared<oneshot::Receiver<bool>>,
}

#[uniffi::export]
impl ToolCallDeadline {
    /// Starts the execution budget immediately before launching the host task.
    #[uniffi::constructor]
    pub fn new(timeout_ms: u32) -> Self {
        Self::with_clock(timeout_ms, now)
    }

    /// Records the first completion; later signals have no effect.
    pub fn complete(&self) {
        self.settle(true);
    }

    /// Returns the shared verdict, without joining late work.
    pub async fn completed_in_time(&self) -> bool {
        loop {
            let remaining = self.expires.saturating_sub((self.clock)());
            if remaining.is_zero() {
                self.settle(false);
                return self
                    .finished
                    .clone()
                    .await
                    .expect("deadline retains sender");
            }
            let timer = std::pin::pin!(sleep_until(self.expires));
            if let Either::Left((result, _)) = select(self.finished.clone(), timer).await {
                return result.expect("deadline retains sender");
            }
        }
    }
}

impl ToolCallDeadline {
    fn with_clock(timeout_ms: u32, clock: fn() -> Duration) -> Self {
        let (sender, receiver) = oneshot::channel();
        Self {
            clock,
            expires: clock() + Duration::from_millis(timeout_ms.into()),
            sender: Mutex::new(Some(sender)),
            finished: receiver.shared(),
        }
    }

    fn settle(&self, completed: bool) {
        if let Some(sender) = self.sender.lock().unwrap().take() {
            let _ = sender.send(completed && (self.clock)() < self.expires);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use futures::executor::block_on;

    #[test]
    fn selects_permission_and_execution_path() {
        use ToolCallAction::*;
        for interactive in [false, true] {
            assert_eq!(
                agent_authorize_call(CallPermission::Ask, true, interactive),
                Prompt
            );
            assert_eq!(
                agent_authorize_call(CallPermission::Never, true, interactive),
                Denied {
                    reason: CallDenial::Policy
                }
            );
            assert_eq!(
                agent_authorize_call(CallPermission::Ask, false, interactive),
                Denied {
                    reason: CallDenial::PromptUnavailable
                }
            );
        }
        assert_eq!(
            agent_authorize_call(CallPermission::Always, false, true),
            Interactive
        );
        assert_eq!(
            agent_authorize_call(CallPermission::Always, false, false),
            timed(None)
        );
        assert_eq!(
            agent_resolve_call_prompt(CallGrant::Once),
            timed(Some(CallGrantScope::Once))
        );
        assert_eq!(
            agent_resolve_call_prompt(CallGrant::ForChat),
            timed(Some(CallGrantScope::ForChat))
        );
        assert_eq!(
            agent_resolve_call_prompt(CallGrant::Deny),
            Denied {
                reason: CallDenial::User
            }
        );
    }

    #[test]
    fn timeout_does_not_wait_for_work_or_accept_late_completion() {
        let deadline = ToolCallDeadline::new(1);
        assert!(!block_on(deadline.completed_in_time()));
        deadline.complete();
        assert!(!block_on(deadline.completed_in_time()));
    }

    #[test]
    fn prompt_wait_is_outside_the_budget_and_expiry_is_inclusive() {
        use std::cell::Cell;
        thread_local! { static MS: Cell<u64> = const { Cell::new(0) }; }
        let clock = || Duration::from_millis(MS.get());
        assert_eq!(
            agent_authorize_call(CallPermission::Ask, true, true),
            ToolCallAction::Prompt
        );
        MS.set(90_000);
        let ToolCallAction::Timed { timeout_ms, .. } = agent_resolve_call_prompt(CallGrant::Once)
        else {
            panic!("expected dispatch")
        };
        let on_time = ToolCallDeadline::with_clock(timeout_ms, clock);
        let at_expiry = ToolCallDeadline::with_clock(timeout_ms, clock);
        MS.set(119_999);
        on_time.complete();
        MS.set(120_000);
        at_expiry.complete();
        assert!(block_on(on_time.completed_in_time()));
        assert!(!block_on(at_expiry.completed_in_time()));
    }

    #[test]
    fn first_completion_wins() {
        let deadline = ToolCallDeadline::new(TIMEOUT_MS);
        deadline.complete();
        deadline.settle(false);
        deadline.complete();
        assert!(block_on(deadline.completed_in_time()));
    }
}
