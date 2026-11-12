use std::{
    io::{Read, Write},
    net::TcpListener,
    process::Command,
    thread,
    time::{Duration, Instant},
};

#[test]
fn discovery_stream_completion_and_errors_run_headless() {
    for (command, status, body, expected, success) in [
        (
            "models",
            "200 OK",
            r#"{"data":[{"id":"z"},{"id":"a"}]}"#,
            "a\nz\n",
            true,
        ),
        (
            "chat",
            "200 OK",
            "event: content_block_delta\ndata: {\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"hello\"}}\n\nevent: message_delta\ndata: {\"delta\":{\"stop_reason\":\"end_turn\"}}\n\nevent: message_stop\ndata: {}\n\n",
            "hello",
            true,
        ),
        ("chat", "403 Forbidden", "denied", "HTTP error 403", false),
        (
            "chat",
            "200 OK",
            "event: error\ndata: {\"error\":{\"type\":\"overloaded_error\",\"message\":\"busy\"}}\n\n",
            "HTTP error 500",
            false,
        ),
    ] {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        listener.set_nonblocking(true).unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        let server = thread::spawn(move || {
            let deadline = Instant::now() + Duration::from_secs(5);
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
            socket
                .set_read_timeout(Some(Duration::from_secs(5)))
                .unwrap();
            socket
                .set_write_timeout(Some(Duration::from_secs(5)))
                .unwrap();
            let mut headers = Vec::new();
            while !headers.ends_with(b"\r\n\r\n") {
                let mut byte = [0];
                socket.read_exact(&mut byte).unwrap();
                headers.push(byte[0]);
            }
            let headers = String::from_utf8(headers).unwrap().to_lowercase();
            assert!(headers.contains("x-api-key: test-key"));
            assert!(!headers.contains("authorization:"));
            let length: usize = headers
                .lines()
                .find_map(|line| {
                    line.strip_prefix("content-length:")
                        .map(|v| v.trim().parse().unwrap())
                })
                .unwrap_or(0);
            assert!(length < 1024 * 1024);
            socket.read_exact(&mut vec![0; length]).unwrap();
            write!(
                socket,
                "HTTP/1.1 {status}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                body.len()
            )
            .unwrap();
        });
        let mut cli = Command::new(env!("CARGO_BIN_EXE_eigin"));
        cli.args([
            "experimental",
            "inference",
            command,
            "--provider",
            "anthropic",
            "--base-url",
            &base,
            "--api-key-env",
            "TEST_ANTHROPIC_KEY",
        ]);
        if command == "chat" {
            cli.args(["--model", "test", "--prompt", "hi"]);
        }
        let output = cli
            .env("TEST_ANTHROPIC_KEY", "test-key")
            .env("NO_PROXY", "127.0.0.1")
            .env("no_proxy", "127.0.0.1")
            .output()
            .unwrap();
        server.join().unwrap();
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
    }
}
