use crate::{agent::*, conversation::ConversationMessage, inference::*};

fn reply(content: &str) -> RoundOutcome {
    RoundOutcome::Reply {
        message: ConversationMessage {
            role: "assistant".into(),
            content: Some(content.into()),
            ..Default::default()
        },
    }
}
fn tools() -> RoundOutcome {
    RoundOutcome::Tools {
        assistant: ConversationMessage::default(),
        calls: vec![],
    }
}
fn recovery(reason: TurnContinuation) -> TurnAction {
    TurnAction::Recover { reason }
}
fn empty_action(turn: &AgentTurn, outcome: RoundOutcome, signals: TurnSignals) -> TurnAction {
    assert_eq!(
        turn.complete_round(outcome).unwrap(),
        TurnAction::CheckEmptyReply
    );
    turn.resolve_empty_reply(signals).unwrap()
}
fn started() -> AgentTurn {
    let turn = AgentTurn::new();
    assert_eq!(turn.begin_round().unwrap(), TurnAction::RequestInference);
    turn
}

#[test]
fn replies_finish_and_only_foundation_whitespace_is_empty() {
    for text in ["Hello", "\u{feff}", "\u{001c}", "\u{200c}"] {
        let turn = started();
        assert_eq!(
            turn.complete_round(reply(text)).unwrap(),
            TurnAction::Finish {
                reason: TurnFinishReason::Reply
            }
        );
        assert_eq!(turn.begin_round(), Err(TurnError::InvalidPhase));
    }
    for text in [
        "",
        " \t\r\n",
        "\u{0085}\u{00a0}\u{1680}\u{2000}\u{200b}\u{2028}\u{2029}\u{202f}\u{205f}\u{3000}",
    ] {
        let turn = started();
        assert_eq!(
            empty_action(&turn, reply(text), TurnSignals::default()),
            recovery(TurnContinuation::MissingReply)
        );
        assert_eq!(turn.begin_round().unwrap(), TurnAction::RequestInference);
        assert_eq!(
            empty_action(&turn, RoundOutcome::Empty, TurnSignals::default()),
            TurnAction::MissingReply
        );
        assert_eq!(turn.begin_round(), Err(TurnError::InvalidPhase));
    }
}

#[test]
fn forty_tool_batches_execute_before_budget_completion() {
    let turn = AgentTurn::new();
    for count in 1..=40 {
        assert_eq!(turn.begin_round().unwrap(), TurnAction::RequestInference);
        assert_eq!(turn.rounds_executed(), count);
        assert_eq!(
            turn.complete_round(tools()).unwrap(),
            TurnAction::ExecuteTools
        );
        assert_eq!(turn.complete_tools(false).unwrap(), TurnAction::Continue);
    }
    assert_eq!(
        turn.begin_round().unwrap(),
        TurnAction::Finish {
            reason: TurnFinishReason::RoundLimit
        }
    );
    assert_eq!(turn.rounds_executed(), 40);
}

#[test]
fn last_round_cannot_recover_but_can_reply() {
    for failure in [
        None,
        Some(TurnFailure::MissingReply),
        Some(TurnFailure::Interruption),
    ] {
        let turn = AgentTurn::new();
        for _ in 0..39 {
            turn.begin_round().unwrap();
            turn.complete_round(tools()).unwrap();
            turn.complete_tools(false).unwrap();
        }
        turn.begin_round().unwrap();
        let action = match failure {
            Some(failure) => turn
                .fail_round(failure, TurnSignals::default(), true)
                .unwrap(),
            None => turn.complete_round(reply("Done")).unwrap(),
        };
        assert_eq!(
            action,
            match failure {
                None => TurnAction::Finish {
                    reason: TurnFinishReason::Reply
                },
                Some(TurnFailure::MissingReply) => TurnAction::MissingReply,
                _ => TurnAction::PropagateFailure,
            }
        );
    }
}

#[test]
fn empty_and_interruption_share_allowance_in_both_orders() {
    for empty_first in [true, false] {
        let turn = started();
        let first = if empty_first {
            TurnFailure::MissingReply
        } else {
            TurnFailure::Interruption
        };
        assert!(matches!(
            turn.fail_round(first, TurnSignals::default(), true)
                .unwrap(),
            TurnAction::Recover { .. }
        ));
        turn.begin_round().unwrap();
        let second = if empty_first {
            TurnFailure::Interruption
        } else {
            TurnFailure::MissingReply
        };
        assert_eq!(
            turn.fail_round(second, TurnSignals::default(), true)
                .unwrap(),
            if empty_first {
                TurnAction::PropagateFailure
            } else {
                TurnAction::MissingReply
            }
        );
    }
}

#[test]
fn local_and_terminal_failures_do_not_recover() {
    for (failure, allow) in [
        (TurnFailure::Terminal, true),
        (TurnFailure::Terminal, false),
        (TurnFailure::Interruption, false),
    ] {
        assert_eq!(
            started()
                .fail_round(failure, TurnSignals::default(), allow)
                .unwrap(),
            TurnAction::PropagateFailure
        );
    }
    assert_eq!(
        started()
            .fail_round(TurnFailure::MissingReply, TurnSignals::default(), false)
            .unwrap(),
        recovery(TurnContinuation::MissingReply)
    );
}

#[test]
fn lifecycle_precedence_matches_each_entry_point() {
    for signals in [
        TurnSignals {
            cancelled: true,
            ..Default::default()
        },
        TurnSignals {
            stopped: true,
            ..Default::default()
        },
        TurnSignals {
            terminate: true,
            ..Default::default()
        },
    ] {
        assert_eq!(
            started()
                .fail_round(TurnFailure::Interruption, signals, true)
                .unwrap(),
            TurnAction::PropagateFailure
        );
        assert_eq!(
            started()
                .fail_round(TurnFailure::MissingReply, signals, true)
                .unwrap(),
            TurnAction::ReturnStopped
        );
        assert_eq!(
            empty_action(&started(), RoundOutcome::Empty, signals),
            if signals.stopped {
                TurnAction::ReturnStopped
            } else if signals.terminate {
                TurnAction::Finish {
                    reason: TurnFinishReason::ExplicitTermination,
                }
            } else {
                TurnAction::Cancelled
            }
        );
    }
    let turn = started();
    turn.complete_round(tools()).unwrap();
    assert_eq!(
        turn.complete_tools(true).unwrap(),
        TurnAction::Finish {
            reason: TurnFinishReason::ExplicitTermination
        }
    );
    assert_eq!(turn.begin_round(), Err(TurnError::InvalidPhase));
}

#[test]
fn invalid_calls_do_not_advance_or_reissue_work() {
    let turn = AgentTurn::new();
    assert_eq!(turn.complete_tools(false), Err(TurnError::InvalidPhase));
    assert_eq!(turn.rounds_executed(), 0);
    turn.begin_round().unwrap();
    assert_eq!(turn.begin_round(), Err(TurnError::InvalidPhase));
    turn.complete_round(tools()).unwrap();
    assert_eq!(turn.complete_round(tools()), Err(TurnError::InvalidPhase));
    turn.complete_tools(false).unwrap();
    assert_eq!(turn.complete_tools(false), Err(TurnError::InvalidPhase));
    assert_eq!(turn.rounds_executed(), 1);
    assert_eq!(AgentTurn::new().rounds_executed(), 0);
}

#[test]
fn local_inline_work_survives_empty_reply_recovery_without_a_batch_action() {
    let turn = started();
    let round = AgentRound::new();
    let call = InferenceToolCall {
        id: "done".into(),
        kind: "function".into(),
        name: "lookup".into(),
        arguments: "{}".into(),
    };
    let completed = round
        .record_inline_exchange(
            call,
            RoundToolResult {
                tool_call_id: "done".into(),
                content: "result".into(),
            },
        )
        .unwrap();
    round
        .accept_event(InferenceEvent::Finished {
            reason: InferenceFinishReason::Stop,
        })
        .unwrap();
    assert_eq!(
        empty_action(
            &turn,
            round.finish_stream().unwrap(),
            TurnSignals::default()
        ),
        recovery(TurnContinuation::MissingReply)
    );
    assert_eq!(completed.len(), 2);
    assert_eq!(completed[1].tool_call_id.as_deref(), Some("done"));
    turn.begin_round().unwrap();
    assert_eq!(
        turn.complete_round(reply("Done")).unwrap(),
        TurnAction::Finish {
            reason: TurnFinishReason::Reply
        }
    );
    assert_eq!(turn.rounds_executed(), 2);
}

#[test]
fn interrupted_cloud_round_yields_recovery_instead_of_executable_calls() {
    let turn = started();
    let round = AgentRound::new();
    round
        .accept_event(InferenceEvent::ContentDelta {
            text: "partial".into(),
        })
        .unwrap();
    round
        .accept_event(InferenceEvent::ToolCall {
            call: InferenceToolCall {
                id: "pending".into(),
                kind: "function".into(),
                name: "lookup".into(),
                arguments: "{".into(),
            },
        })
        .unwrap();
    assert_eq!(
        turn.fail_round(TurnFailure::Interruption, TurnSignals::default(), true)
            .unwrap(),
        recovery(TurnContinuation::Interrupted)
    );
    assert_eq!(round.partial_content(), "partial");
    assert_eq!(turn.complete_tools(false), Err(TurnError::InvalidPhase));
    assert_eq!(turn.begin_round().unwrap(), TurnAction::RequestInference);
}
