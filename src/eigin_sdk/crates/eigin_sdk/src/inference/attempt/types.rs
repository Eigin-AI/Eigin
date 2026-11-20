/// Work to perform in order. Handle 0 is the original primary, 1 is the hedge;
/// replacements receive fresh handles. The host retains errors and buffered events by handle.
/// Deliver replays the winning buffer before the current event. Lose cancels the losing
/// side (including pending replacements) and records its silence. Finish tears down all work.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Enum)]
pub enum AttemptAction {
    Open {
        id: u64,
    },
    CancelOpening {
        id: u64,
    },
    Forward {
        id: u64,
    },
    RecordOpenFailure {
        id: u64,
    },
    Buffer,
    Overflow,
    Win {
        id: u64,
    },
    Lose {
        id: u64,
    },
    Deliver,
    Chase {
        failed: u64,
        replacement: u64,
        timeout: bool,
    },
    Finish {
        error_source: u64,
        timeout: bool,
    },
}

/// Payload facts supplied by the host without crossing the binding with text or arguments.
#[derive(Clone, Copy, Debug, uniffi::Enum)]
pub enum AttemptEvent {
    Content {
        nonempty: bool,
    },
    ToolCall {
        has_id: bool,
        has_name: bool,
        object_arguments: bool,
    },
    Ancillary,
}
impl AttemptEvent {
    pub(super) fn wins(self) -> bool {
        matches!(
            self,
            Self::Content { nonempty: true }
                | Self::ToolCall {
                    has_id: true,
                    has_name: true,
                    object_arguments: true
                }
        )
    }
}

/// Input without host payloads. Send Opened after dispatch, including replacement dispatch.
/// NoReplacement retains the error that started that chase. Late events and clocks are inert.
#[derive(Debug, Clone, Copy, uniffi::Enum)]
pub enum AttemptObservation {
    Start {
        hedge_delay_ms: Option<u32>,
        ceiling_ms: u32,
    },
    Opened {
        id: u64,
    },
    Event {
        id: u64,
        kind: AttemptEvent,
        bytes: u64,
    },
    OpenFailed {
        id: u64,
    },
    Ended {
        id: u64,
    },
    NoReplacement {
        id: u64,
    },
    Cancel,
}

/// Ordered host work after an undecided primary failed. Record before refreshing or ranking.
#[derive(uniffi::Record)]
pub struct ReplacementWork {
    pub record_model: Option<String>,
    pub refresh: bool,
    pub rank: bool,
}
