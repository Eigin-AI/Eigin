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
        run_chat(authenticated, "compatible");
    }
    run_chat(true, "relay");
    run_chat(true, "responses");
}

fn run_chat(authenticated: bool, provider: &'static str) {
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
        if provider == "responses" {
            assert!(headers.starts_with("POST /responses "));
            socket
                .write_all(
                    b"data: {\"type\":\"response.output_text.delta\",\"delta\":\"hello\"}\n\n",
                )
                .unwrap();
        } else {
            socket.write_all(b"data: {\"choices\":[{\"delta\":{\"content\":\"hello\"},\"finish_reason\":null}]}\n\n").unwrap();
        }
        // Leave the response unfinished until the CLI cancels it.
        assert_eq!(socket.read(&mut [0]).unwrap(), 0);
    });

    let mut command = Command::new(env!("CARGO_BIN_EXE_eigin"));
    if provider == "responses" {
        command.args([
            "experimental",
            "inference",
            "chat",
            "--provider",
            "openai-responses",
            "--api-key-env",
            "EIGIN_TEST_API_KEY",
        ]);
    } else if provider == "relay" {
        command.args([
            "experimental",
            "inference",
            "chat",
            "--provider",
            "eigin-relay",
            "--relay-key-env",
            "EIGIN_RELAY_KEY",
            "--credit-token-env",
            "EIGIN_TEST_API_KEY",
        ]);
    } else if authenticated {
        command.args([
            "experimental",
            "inference",
            "chat",
            "--api-key-env",
            "EIGIN_TEST_API_KEY",
        ]);
    } else {
        command.args(["experimental", "inference", "chat", "--no-auth"]);
    }
    let mut cli = CliProcess(
        command
            .args(["--base-url", &base, "--model", "test", "--prompt", "hello"])
            .env("EIGIN_RELAY_KEY", "relay-key")
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

#[test]
fn relay_failover_uses_distinct_wallets_and_explicit_relay_key() {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    listener.set_nonblocking(true).unwrap();
    let base = format!("http://{}", listener.local_addr().unwrap());
    let server = thread::spawn(move || {
        for (token, status, body) in [
            ("first", "402 Payment Required", ""),
            (
                "second",
                "200 OK",
                "data: {\"choices\":[{\"delta\":{\"content\":\"hello\"},\"finish_reason\":\"stop\"}]}\n\n",
            ),
        ] {
            let deadline = Instant::now() + TIMEOUT;
            let mut socket = loop {
                match listener.accept() {
                    Ok((socket, _)) => break socket,
                    Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                        assert!(Instant::now() < deadline, "missing relay attempt");
                        thread::sleep(Duration::from_millis(5));
                    }
                    Err(e) => panic!("{e}"),
                }
            };
            socket.set_nonblocking(false).unwrap();
            socket.set_nonblocking(false).unwrap();
            socket.set_read_timeout(Some(TIMEOUT)).unwrap();
            let request = drain_request(&mut socket).to_lowercase();
            assert!(request.starts_with("post /v1/chat/completions "));
            assert!(request.contains(&format!("authorization: bearer {token}\r\n")));
            assert!(request.contains("x-eigin-key: relay-key\r\n"));
            write!(
                socket,
                "HTTP/1.1 {status}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                body.len()
            )
            .unwrap();
        }
    });
    let output = Command::new(env!("CARGO_BIN_EXE_eigin"))
        .args([
            "experimental",
            "inference",
            "chat",
            "--provider",
            "eigin-relay",
            "--base-url",
            &base,
            "--relay-key-env",
            "RELAY_KEY",
            "--credit-token-env",
            "WALLET_A",
            "--credit-token-env",
            "WALLET_B",
            "--model",
            "test",
            "--prompt",
            "hi",
        ])
        .env("RELAY_KEY", "relay-key")
        .env("WALLET_A", "first")
        .env("WALLET_B", "second")
        .env("NO_PROXY", "127.0.0.1")
        .env("no_proxy", "127.0.0.1")
        .output()
        .unwrap();
    server.join().unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(String::from_utf8(output.stdout).unwrap(), "hello\n");
}

#[test]
fn responses_models_tools_and_subscription_errors_run_headless() {
    for (command, path, status, body, expected, success) in [
        (
            "models",
            "/models",
            "200 OK",
            "{\"models\":[{\"slug\":\"z\"},{\"slug\":\"a\"}]}",
            "z\na\n",
            true,
        ),
        (
            "chat",
            "/responses",
            "200 OK",
            "data: {\"type\":\"response.output_item.done\",\"item\":{\"type\":\"function_call\",\"call_id\":\"c\",\"name\":\"weather\",\"arguments\":\"{}\"}}\n\ndata: {\"type\":\"response.completed\"}\n\n",
            "\"name\":\"weather\"",
            true,
        ),
        (
            "chat",
            "/responses",
            "403 Forbidden",
            "subscription_sharing_user_not_eligible",
            "not eligible",
            false,
        ),
    ] {
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
            let headers = drain_request(&mut socket);
            assert!(headers.lines().next().unwrap().contains(path));
            write!(socket,"HTTP/1.1 {status}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",body.len()).unwrap();
        });
        let mut cli = Command::new(env!("CARGO_BIN_EXE_eigin"));
        cli.args([
            "experimental",
            "inference",
            command,
            "--provider",
            "openai-responses",
            "--api-key-env",
            "TEST_RESPONSES_TOKEN",
            "--base-url",
            &base,
        ]);
        if command == "chat" {
            cli.args(["--model", "test", "--prompt", "hi"]);
        }
        let output = cli
            .env("TEST_RESPONSES_TOKEN", "test")
            .env("NO_PROXY", "127.0.0.1")
            .env("no_proxy", "127.0.0.1")
            .output()
            .unwrap();
        assert_eq!(
            output.status.success(),
            success,
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        let text = String::from_utf8_lossy(if success {
            &output.stdout
        } else {
            &output.stderr
        });
        assert!(text.contains(expected), "{text}");
        server.join().unwrap();
    }
}
