use super::{super::*, fixtures::*};
use futures::{FutureExt, executor::block_on};
use std::sync::{Arc, atomic::Ordering};

#[test]
fn ordered_output_and_eof_release_native_work() {
    let host = Arc::new(Host::default());
    let events = vec![
        InferenceEvent::ContentDelta {
            text: "hello".into(),
        },
        InferenceEvent::Finished {
            reason: crate::inference::InferenceFinishReason::Stop,
        },
    ];
    host.events.lock().unwrap().extend(events.clone());
    let stream = stream(host.clone());
    block_on(stream.open()).unwrap();
    for event in events {
        assert_eq!(block_on(stream.next()).unwrap(), Some(event));
    }
    assert!(block_on(stream.next()).unwrap().is_none());
    assert!(block_on(stream.next()).unwrap().is_none());
    stream.cancel();
    drop(stream);
    assert_eq!(host.closes.load(Ordering::SeqCst), 1);
}

#[test]
fn cancellation_and_abandoned_futures_wake_pending_work() {
    for opening in [true, false] {
        for abandon in [true, false] {
            let host = Arc::new(Host {
                delay_open: opening,
                delay_read: !opening,
                ..Default::default()
            });
            let stream = stream(host.clone());
            if !opening {
                block_on(stream.open()).unwrap();
            }
            let mut pending = Box::pin(async {
                if opening {
                    stream.open().await
                } else {
                    stream.next().await.map(|_| ())
                }
            });
            assert!(pending.as_mut().now_or_never().is_none());
            assert!(matches!(block_on(stream.next()), Err(InferenceError::Busy)));
            if abandon {
                drop(pending);
            } else {
                stream.cancel();
                assert!(matches!(block_on(pending), Err(InferenceError::Cancelled)));
            }
            if let Some(c) = host.open.lock().unwrap().take() {
                c.succeed();
            }
            if let Some(c) = host.read.lock().unwrap().take() {
                c.succeed(Some(InferenceEvent::ContentDelta {
                    text: "late".into(),
                }));
            }
            assert!(matches!(
                block_on(stream.next()),
                Err(InferenceError::Cancelled)
            ));
            stream.cancel();
            assert_eq!(host.closes.load(Ordering::SeqCst), 1);
        }
    }
}

#[test]
fn typed_open_and_stream_failures_close_host_resources() {
    for opening in [true, false] {
        let host = Arc::new(Host {
            delay_open: opening,
            delay_read: !opening,
            ..Default::default()
        });
        let stream = stream(host.clone());
        if !opening {
            block_on(stream.open()).unwrap();
        }
        let mut pending = Box::pin(async {
            if opening {
                stream.open().await
            } else {
                stream.next().await.map(|_| ())
            }
        });
        assert!(pending.as_mut().now_or_never().is_none());
        let error = InferenceError::LocalUnavailable {
            code: "not_downloaded".into(),
            reason: "Download the model".into(),
        };
        if opening {
            host.open.lock().unwrap().take().unwrap().fail(error);
        } else {
            host.read.lock().unwrap().take().unwrap().fail(error);
        }
        assert!(matches!(
            block_on(pending),
            Err(InferenceError::LocalUnavailable { .. })
        ));
        assert_eq!(host.closes.load(Ordering::SeqCst), 1);
    }
}
