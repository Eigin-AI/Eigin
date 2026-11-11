#![cfg(unix)]

use std::{
    io::{Read, Write},
    net::{TcpListener, TcpStream},
    process::{Child, Command, Stdio},
    sync::mpsc,
    thread,
    time::{Duration, Instant},
};

const TIMEOUT: Duration = Duration::from_secs(5);

struct CliProcess(Child);

impl Drop for CliProcess {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

#[test]
fn chat_auth_choices_preserve_partial_output_and_ctrl_c_failure() {
    for authenticated in [false, true] {
        run_chat(authenticated);
    }
}

fn run_chat(authenticated: bool) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    listener.set_nonblocking(true).unwrap();
    let base = format!("http://{}", listener.local_addr().unwrap());
    let server = thread::spawn(move || {
        let deadline = Instant::now() + TIMEOUT;
        let mut socket = loop {
            match listener.accept() {
                Ok((socket, _)) => break socket,
                Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                    assert!(Instant::now() < deadline, "CLI did not connect");
                    thread::sleep(Duration::from_millis(5));
                }
                Err(error) => panic!("{error}"),
            }
        };
        socket.set_nonblocking(false).unwrap();
        socket.set_read_timeout(Some(TIMEOUT)).unwrap();
        socket.set_write_timeout(Some(TIMEOUT)).unwrap();
        let headers = drain_request(&mut socket);
        let authorization = headers.lines().find_map(|line| {
            let (name, value) = line.split_once(':')?;
            name.eq_ignore_ascii_case("authorization")
                .then(|| value.trim())
        });
        assert_eq!(
            authorization,
            authenticated.then_some("Bearer selected-test-key")
        );
        socket.write_all(b"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nContent-Length: 99999\r\n\r\n").unwrap();
        socket.write_all(b"data: {\"choices\":[{\"delta\":{\"content\":\"hello\"},\"finish_reason\":null}]}\n\n").unwrap();
        // Leave the response unfinished until the CLI cancels it.
        assert_eq!(socket.read(&mut [0]).unwrap(), 0);
    });

    let mut command = Command::new(env!("CARGO_BIN_EXE_eigin"));
    if authenticated {
        command.args(["inference", "chat", "--api-key-env", "EIGIN_TEST_API_KEY"]);
    } else {
        command.args(["inference", "chat", "--no-auth"]);
    }
    let mut cli = CliProcess(
        command
            .args(["--base-url", &base, "--model", "test", "--prompt", "hello"])
            .env("EIGIN_TEST_API_KEY", "selected-test-key")
            .env("OPENAI_API_KEY", "must-not-be-sent")
            .env("NO_PROXY", "127.0.0.1")
            .env("no_proxy", "127.0.0.1")
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap(),
    );
    let mut stdout = cli.0.stdout.take().unwrap();
    let (output, received) = mpsc::channel();
    let reader = thread::spawn(move || {
        let mut bytes = [0; 5];
        let result = stdout.read_exact(&mut bytes).map(|()| bytes);
        let _ = output.send(result);
    });
    assert_eq!(received.recv_timeout(TIMEOUT).unwrap().unwrap(), *b"hello");
    assert!(
        cli.0.try_wait().unwrap().is_none(),
        "response must still be pending"
    );

    let pid = cli.0.id().to_string();
    assert!(
        Command::new("kill")
            .args(["-INT", &pid])
            .status()
            .unwrap()
            .success()
    );
    let deadline = Instant::now() + TIMEOUT;
    let status = loop {
        if let Some(status) = cli.0.try_wait().unwrap() {
            break status;
        }
        assert!(Instant::now() < deadline, "CLI did not exit after Ctrl-C");
        thread::sleep(Duration::from_millis(5));
    };
    assert!(!status.success());
    let mut error = String::new();
    cli.0
        .stderr
        .take()
        .unwrap()
        .read_to_string(&mut error)
        .unwrap();
    assert!(error.contains("cancel"), "{error}");
    reader.join().unwrap();
    server.join().unwrap();
}

fn drain_request(socket: &mut TcpStream) -> String {
    let mut headers = Vec::new();
    while !headers.ends_with(b"\r\n\r\n") {
        let mut byte = [0];
        socket.read_exact(&mut byte).unwrap();
        headers.push(byte[0]);
    }
    let headers = String::from_utf8(headers).unwrap();
    let length: usize = headers
        .lines()
        .find_map(|line| {
            let (name, value) = line.split_once(':')?;
            name.eq_ignore_ascii_case("content-length")
                .then(|| value.trim().parse().unwrap())
        })
        .unwrap_or(0);
    assert!(length < 1024 * 1024);
    socket.read_exact(&mut vec![0; length]).unwrap();
    headers
}
