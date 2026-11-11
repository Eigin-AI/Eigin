#![cfg(not(target_arch = "wasm32"))]

use eigin_sdk::http::*;
use futures::executor::block_on;
use std::{
    io::{Read, Write},
    net::{TcpListener, TcpStream},
    sync::{Arc, mpsc},
    thread,
    time::Duration,
};

const TIMEOUT: Duration = Duration::from_secs(3);

// Each test owns one connection; no provider protocol or external process is involved.
fn serve(response: impl FnOnce(TcpStream) + Send + 'static) -> (String, thread::JoinHandle<()>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    let thread = thread::spawn(move || {
        let (mut socket, _) = listener.accept().unwrap();
        socket.set_read_timeout(Some(TIMEOUT)).unwrap();
        socket.set_write_timeout(Some(TIMEOUT)).unwrap();
        let mut headers = Vec::new();
        while !headers.ends_with(b"\r\n\r\n") {
            let mut byte = [0];
            socket.read_exact(&mut byte).unwrap();
            headers.push(byte[0]);
        }
        response(socket);
    });
    (url, thread)
}

fn request(url: String) -> HttpRequest {
    HttpRequest {
        url,
        method: "GET".into(),
        headers: [("Authorization".into(), "Bearer test-secret".into())].into(),
        body: vec![],
    }
}

fn operation() -> Arc<HttpOperation> {
    HttpOperation::with_transport(Arc::new(DefaultHttpTransport::new().unwrap()))
}

#[test]
fn default_http_delivers_bytes_before_eof_without_an_ambient_tokio_runtime() {
    let (resume, paused) = mpsc::channel();
    let (url, server) = serve(move |mut socket| {
        socket
            .write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 11\r\nConnection: close\r\n\r\nhello")
            .unwrap();
        paused.recv_timeout(TIMEOUT).unwrap();
        socket.write_all(b" world").unwrap();
    });
    let op = operation();
    assert_eq!(block_on(op.send(request(url))).unwrap().status, 200);
    let mut bytes = block_on(op.read()).unwrap().unwrap();
    while bytes.len() < 5 {
        bytes.extend(block_on(op.read()).unwrap().unwrap());
    }
    assert_eq!(bytes, b"hello");
    resume.send(()).unwrap();
    while let Some(chunk) = block_on(op.read()).unwrap() {
        bytes.extend(chunk);
    }
    assert_eq!(bytes, b"hello world");
    server.join().unwrap();
}

#[test]
fn cancellation_closes_the_socket_before_headers_and_during_body() {
    for send_headers in [false, true] {
        let (arrived, received) = mpsc::channel();
        let (url, server) = serve(move |mut socket| {
            if send_headers {
                socket
                    .write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\nx")
                    .unwrap();
            }
            arrived.send(()).unwrap();
            let mut byte = [0];
            assert_eq!(
                socket.read(&mut byte).unwrap(),
                0,
                "cancel must close the socket"
            );
        });
        let op = operation();
        let worker = op.clone();
        let (reading, ready) = mpsc::channel();
        let task = thread::spawn(move || {
            block_on(async {
                worker.send(request(url)).await?;
                if send_headers {
                    assert!(worker.read().await?.is_some());
                    reading.send(()).unwrap();
                }
                while worker.read().await?.is_some() {}
                Ok::<_, HttpTransportError>(())
            })
        });
        received.recv_timeout(TIMEOUT).unwrap();
        if send_headers {
            ready.recv_timeout(TIMEOUT).unwrap();
        }
        op.cancel();
        assert!(matches!(
            task.join().unwrap(),
            Err(HttpTransportError::Cancelled)
        ));
        server.join().unwrap();
    }
}

#[test]
fn cross_origin_redirects_never_reach_the_destination() {
    let destination = TcpListener::bind("127.0.0.1:0").unwrap();
    destination.set_nonblocking(true).unwrap();
    let location = format!("http://{}/private", destination.local_addr().unwrap());
    let (url, server) = serve(move |mut socket| {
        write!(socket, "HTTP/1.1 307 Temporary Redirect\r\nLocation: {location}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n").unwrap();
    });
    let op = operation();
    assert_eq!(block_on(op.send(request(url))).unwrap().status, 307);
    assert_eq!(
        destination.accept().unwrap_err().kind(),
        std::io::ErrorKind::WouldBlock
    );
    op.cancel();
    server.join().unwrap();
}
