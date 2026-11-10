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
    let worker = std::thread::spawn(|| emit(DiagnosticLevel::Info, "test", "Blocked", |_| None));
    entered_rx
        .recv_timeout(std::time::Duration::from_secs(5))
        .unwrap();
    clear_diagnostic_receiver();
    assert_eq!(drops.load(Ordering::SeqCst), 0);
    finish_tx.send(()).unwrap();
    worker.join().unwrap();
    assert_eq!(drops.load(Ordering::SeqCst), 1);
}
