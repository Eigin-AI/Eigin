use super::{ChatTurn, ChatTurnError};
use crate::agent::TurnOutputEntry;
#[cfg(not(target_arch = "wasm32"))]
use futures_util::future::BoxFuture;
use std::{future::Future, sync::Arc};

/// Running turn future; browser timers are confined to the WASM execution thread.
#[cfg(target_arch = "wasm32")]
pub type ChatTurnFuture =
    futures_util::future::LocalBoxFuture<'static, Result<Vec<TurnOutputEntry>, ChatTurnError>>;
/// Running turn future, movable between native executor threads.
#[cfg(not(target_arch = "wasm32"))]
pub type ChatTurnFuture = BoxFuture<'static, Result<Vec<TurnOutputEntry>, ChatTurnError>>;

pub(super) struct Running {
    pub(super) turn: Arc<ChatTurn>,
    pub(super) work: ChatTurnFuture,
}

impl Future for Running {
    type Output = Result<Vec<TurnOutputEntry>, ChatTurnError>;
    fn poll(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<Self::Output> {
        let result = std::task::ready!(self.work.as_mut().poll(cx));
        self.turn.close();
        std::task::Poll::Ready(match result {
            Err(ChatTurnError::Stopped) => Ok(vec![]),
            result => result,
        })
    }
}

impl Drop for Running {
    fn drop(&mut self) {
        self.turn.close();
    }
}
