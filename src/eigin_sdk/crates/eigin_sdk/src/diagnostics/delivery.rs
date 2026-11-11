//! Host receiver registration, filtering, and event delivery.

use std::{
    cell::Cell,
    sync::{Arc, Mutex},
};

use super::event::{
    DiagnosticContext, DiagnosticEvent, DiagnosticField, DiagnosticLevel, DiagnosticPrivacy,
};

/// Filtering applied before values are formatted or cross the host boundary.
#[derive(Clone, Copy, Debug, uniffi::Record)]
pub struct DiagnosticOptions {
    pub minimum_level: DiagnosticLevel,
    pub include_private: bool,
}

impl Default for DiagnosticOptions {
    fn default() -> Self {
        Self {
            minimum_level: DiagnosticLevel::Debug,
            include_private: false,
        }
    }
}

/// Host destination. Calls are synchronous and may arrive concurrently on native hosts.
/// Implementations must return quickly, never throw, and not call SDK operations.
#[uniffi::export(callback_interface)]
pub trait DiagnosticReceiver: Send + Sync {
    /// Receives a new event with private values already withheld unless opted in.
    fn receive(&self, event: DiagnosticEvent);
}

#[derive(Clone)]
struct Registration {
    receiver: Arc<dyn DiagnosticReceiver>,
    options: DiagnosticOptions,
}

static REGISTRATION: Mutex<Option<Registration>> = Mutex::new(None);
thread_local! { static DELIVERING: Cell<bool> = const { Cell::new(false) }; }

/// Replaces this SDK runtime's receiver. In-flight callbacks may still finish.
#[uniffi::export]
pub fn set_diagnostic_receiver(receiver: Box<dyn DiagnosticReceiver>, options: DiagnosticOptions) {
    let old = REGISTRATION.lock().unwrap().replace(Registration {
        receiver: receiver.into(),
        options,
    });
    // Host destruction can call foreign code; never hold the registration lock across it.
    drop(old);
}

/// Updates filtering for subsequent snapshots; already delivered values cannot be recalled.
#[uniffi::export]
pub fn update_diagnostic_options(options: DiagnosticOptions) {
    if let Some(registration) = REGISTRATION.lock().unwrap().as_mut() {
        registration.options = options;
    }
}

/// Detaches the receiver. In-flight callbacks retain it until they finish.
#[uniffi::export]
pub fn clear_diagnostic_receiver() {
    let old = REGISTRATION.lock().unwrap().take();
    drop(old);
}

/// Builder available only after the receiver and severity filters pass.
pub(crate) struct EventBuilder {
    include_private: bool,
    fields: Vec<DiagnosticField>,
}

impl EventBuilder {
    pub(crate) fn field(
        &mut self,
        name: &str,
        privacy: DiagnosticPrivacy,
        value: impl FnOnce() -> String,
    ) {
        let value = (privacy == DiagnosticPrivacy::Public || self.include_private).then(value);
        self.fields.push(DiagnosticField {
            name: name.into(),
            privacy,
            value,
        });
    }
}

/// Emits lazily so disabled diagnostics do not format fields or context.
pub(crate) fn emit(
    level: DiagnosticLevel,
    component: &'static str,
    message: &'static str,
    build: impl FnOnce(&mut EventBuilder) -> Option<DiagnosticContext>,
) {
    if DELIVERING.get() {
        return;
    }
    let snapshot = REGISTRATION.lock().unwrap().clone();
    let Some(registration) = snapshot else {
        return;
    };
    if level < registration.options.minimum_level {
        return;
    }
    struct DeliveryGuard;
    impl Drop for DeliveryGuard {
        fn drop(&mut self) {
            DELIVERING.set(false);
        }
    }
    DELIVERING.set(true);
    let _guard = DeliveryGuard;
    let mut builder = EventBuilder {
        include_private: registration.options.include_private,
        fields: Vec::new(),
    };
    let context = build(&mut builder);
    registration.receiver.receive(DiagnosticEvent {
        level,
        component: component.into(),
        message: message.into(),
        context,
        fields: builder.fields,
    });
}

#[cfg(test)]
pub(crate) mod tests {
    // Serialize tests that register or emit through the global receiver.
    pub(crate) static RECEIVER_TEST_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    struct Receiver {
        events: Arc<Mutex<Vec<DiagnosticEvent>>>,
        drops: Arc<AtomicUsize>,
    }
    impl Drop for Receiver {
        fn drop(&mut self) {
            self.drops.fetch_add(1, Ordering::SeqCst);
        }
    }
    impl DiagnosticReceiver for Receiver {
        fn receive(&self, event: DiagnosticEvent) {
            // Recursive emission is dropped rather than recursing or deadlocking.
            emit(DiagnosticLevel::Error, "recursive", "Recursive", |_| {
                panic!("recursive delivery")
            });
            self.events.lock().unwrap().push(event);
        }
    }

    #[test]
    fn filters_privacy_and_manages_receiver_lifetime_under_concurrency() {
        let _registration = RECEIVER_TEST_LOCK.lock().unwrap();
        clear_diagnostic_receiver();
        emit(DiagnosticLevel::Info, "test", "Silent", |_| {
            panic!("no receiver")
        });
        let events = Arc::new(Mutex::new(Vec::new()));
        let drops = Arc::new(AtomicUsize::new(0));
        let receiver = || {
            Box::new(Receiver {
                events: events.clone(),
                drops: drops.clone(),
            }) as Box<dyn DiagnosticReceiver>
        };
        set_diagnostic_receiver(receiver(), DiagnosticOptions::default());
        let send = || {
            emit(DiagnosticLevel::Info, "test", "Event", |event| {
                event.field("public", DiagnosticPrivacy::Public, || "safe".into());
                event.field("private", DiagnosticPrivacy::Private, || {
                    panic!("private formatted")
                });
                None
            })
        };
        send();
        {
            let events = events.lock().unwrap();
            assert_eq!(events[0].fields[0].value.as_deref(), Some("safe"));
            assert_eq!(events[0].fields[1].value, None);
        }
        update_diagnostic_options(DiagnosticOptions {
            minimum_level: DiagnosticLevel::Error,
            include_private: false,
        });
        emit(DiagnosticLevel::Info, "test", "Filtered", |_| {
            panic!("filtered formatting")
        });
        update_diagnostic_options(DiagnosticOptions {
            include_private: true,
            ..Default::default()
        });
        emit(DiagnosticLevel::Info, "test", "Enabled", |event| {
            event.field("private", DiagnosticPrivacy::Private, || "sensitive".into());
            None
        });
        assert_eq!(
            events.lock().unwrap()[1].fields[0].value.as_deref(),
            Some("sensitive")
        );
        update_diagnostic_options(DiagnosticOptions::default());
        std::thread::scope(|scope| {
            for _ in 0..8 {
                scope.spawn(send);
            }
        });
        assert_eq!(events.lock().unwrap().len(), 10);
        set_diagnostic_receiver(receiver(), DiagnosticOptions::default());
        assert_eq!(drops.load(Ordering::SeqCst), 1);
        clear_diagnostic_receiver();
        assert_eq!(drops.load(Ordering::SeqCst), 2);
        send();
        assert_eq!(events.lock().unwrap().len(), 10);
        verify_in_flight_release();
    }

    fn verify_in_flight_release() {
        struct BlockingReceiver {
            entered: std::sync::mpsc::Sender<()>,
            finish: Mutex<std::sync::mpsc::Receiver<()>>,
            drops: Arc<AtomicUsize>,
        }
        impl DiagnosticReceiver for BlockingReceiver {
            fn receive(&self, _: DiagnosticEvent) {
                self.entered.send(()).unwrap();
                self.finish.lock().unwrap().recv().unwrap();
            }
        }
        impl Drop for BlockingReceiver {
            fn drop(&mut self) {
                self.drops.fetch_add(1, Ordering::SeqCst);
            }
        }
        let drops = Arc::new(AtomicUsize::new(0));
        let (entered_tx, entered_rx) = std::sync::mpsc::channel();
        let (finish_tx, finish_rx) = std::sync::mpsc::channel();
        set_diagnostic_receiver(
            Box::new(BlockingReceiver {
                entered: entered_tx,
                finish: Mutex::new(finish_rx),
                drops: drops.clone(),
            }),
            DiagnosticOptions::default(),
        );
        let worker =
            std::thread::spawn(|| emit(DiagnosticLevel::Info, "test", "Blocked", |_| None));
        entered_rx
            .recv_timeout(std::time::Duration::from_secs(5))
            .unwrap();
        clear_diagnostic_receiver();
        assert_eq!(drops.load(Ordering::SeqCst), 0);
        finish_tx.send(()).unwrap();
        worker.join().unwrap();
        assert_eq!(drops.load(Ordering::SeqCst), 1);
    }
}
