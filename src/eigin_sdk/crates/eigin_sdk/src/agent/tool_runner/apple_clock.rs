//! Sleep-inclusive Apple deadlines. One kqueue worker serves all active waiters.
use futures_channel::oneshot;
use std::{
    collections::HashMap,
    io, ptr,
    sync::{
        Mutex, OnceLock,
        atomic::{AtomicU64, Ordering},
    },
    time::Duration,
};

#[repr(C)]
struct Timebase {
    numer: u32,
    denom: u32,
}

unsafe extern "C" {
    fn mach_timebase_info(base: *mut Timebase) -> i32;
    fn mach_continuous_time() -> u64;
}

fn timebase() -> &'static Timebase {
    static BASE: OnceLock<Timebase> = OnceLock::new();
    BASE.get_or_init(|| {
        let mut base = Timebase { numer: 0, denom: 0 };
        assert_eq!(unsafe { mach_timebase_info(&mut base) }, 0);
        base
    })
}

pub(super) fn now() -> Duration {
    let base = timebase();
    let nanos = u128::from(unsafe { mach_continuous_time() }) * u128::from(base.numer)
        / u128::from(base.denom);
    Duration::from_nanos(nanos as u64)
}

struct Timers {
    fd: i32,
    pending: Mutex<HashMap<u64, oneshot::Sender<()>>>,
}

fn timers() -> &'static Timers {
    static QUEUE: OnceLock<Timers> = OnceLock::new();
    static WORKER: std::sync::Once = std::sync::Once::new();
    let queue = QUEUE.get_or_init(|| {
        let fd = unsafe { libc::kqueue() };
        assert!(fd >= 0, "kqueue: {}", io::Error::last_os_error());
        Timers {
            fd,
            pending: Mutex::default(),
        }
    });
    WORKER.call_once(|| {
        std::thread::Builder::new()
            .name("eigin-tool-deadlines".into())
            .spawn(move || {
                loop {
                    let mut event = change(0, 0, 0);
                    let count = unsafe {
                        libc::kevent64(queue.fd, ptr::null(), 0, &mut event, 1, 0, ptr::null())
                    };
                    if count < 0 && io::Error::last_os_error().kind() == io::ErrorKind::Interrupted
                    {
                        continue;
                    }
                    assert_eq!(count, 1, "kevent: {}", io::Error::last_os_error());
                    let sender = queue.pending.lock().unwrap().remove(&event.ident);
                    if let Some(sender) = sender {
                        let _ = sender.send(());
                    }
                }
            })
            .expect("start tool timer worker");
    });
    queue
}

fn change(id: u64, flags: u16, ticks: i64) -> libc::kevent64_s {
    libc::kevent64_s {
        ident: id,
        filter: libc::EVFILT_TIMER,
        flags,
        fflags: libc::NOTE_ABSOLUTE | libc::NOTE_MACHTIME | libc::NOTE_MACH_CONTINUOUS_TIME,
        data: ticks,
        udata: 0,
        ext: [0; 2],
    }
}

fn submit(queue: &Timers, event: libc::kevent64_s) -> io::Result<()> {
    let result = unsafe { libc::kevent64(queue.fd, &event, 1, ptr::null_mut(), 0, 0, ptr::null()) };
    if result < 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(())
    }
}

struct Registration(u64);
impl Drop for Registration {
    fn drop(&mut self) {
        let queue = timers();
        if queue.pending.lock().unwrap().remove(&self.0).is_some() {
            // Delivery may already have removed the kernel's one-shot event.
            let _ = submit(queue, change(self.0, libc::EV_DELETE, 0));
        }
    }
}

pub(super) async fn sleep_until(expires: Duration) {
    static NEXT: AtomicU64 = AtomicU64::new(1);
    let queue = timers();
    let id = NEXT.fetch_add(1, Ordering::Relaxed);
    let base = timebase();
    let ticks = (expires.as_nanos() * u128::from(base.denom)).div_ceil(u128::from(base.numer));
    let (sender, receiver) = oneshot::channel();
    queue.pending.lock().unwrap().insert(id, sender);
    let _registration = Registration(id);
    submit(
        queue,
        change(id, libc::EV_ADD | libc::EV_ONESHOT, ticks as i64),
    )
    .expect("register tool deadline");
    let _ = receiver.await;
}
