#if DEBUG || EIGIN_DEV
import Foundation
import Network

/// A loopback IMAP server that serves MIME fixtures and records requested body sections.
final class FixtureIMAPServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "FixtureIMAPServer")
    private let listener: NWListener
    private let structure: String
    private let bodies: [String: Data]
    private var connections: [NWConnection] = []
    private var sections: [String] = []
    private var resolved = false

    init(structure: String, bodies: [String: Data]) throws {
        self.structure = structure
        self.bodies = bodies
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    var fetchedSections: [String] {
        queue.sync { sections }
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                listener.stateUpdateHandler = { [self] state in
                    guard !resolved else { return }
                    switch state {
                    case .ready:
                        resolved = true
                        continuation.resume(returning: listener.port!.rawValue)
                    case .failed(let error):
                        resolved = true
                        continuation.resume(throwing: error)
                    case .cancelled:
                        resolved = true
                        continuation.resume(throwing: CancellationError())
                    default: break
                    }
                }
                listener.newConnectionHandler = { [self] connection in
                    connections.append(connection)
                    connection.start(queue: queue)
                    send("* OK [CAPABILITY IMAP4rev1] Fixture ready\r\n", to: connection)
                    receive(connection, buffered: Data())
                }
                listener.start(queue: queue)
            }
        }
    }

    func stop() {
        queue.sync {
            listener.cancel()
            connections.forEach { $0.cancel() }
            connections.removeAll()
        }
    }

    private func receive(_ connection: NWConnection, buffered: Data) {
        connection
            .receive(
                minimumIncompleteLength: 1,
                maximumLength: 65536
            ) { [self] data, _, complete, error in
                var buffer = buffered
                if let data { buffer.append(data) }
                while let range = buffer.range(of: Data("\r\n".utf8)) {
                    let command = String(decoding: buffer[..<range.lowerBound], as: UTF8.self)
                    buffer.removeSubrange(..<range.upperBound)
                    respond(command, to: connection)
                }
                if !complete, error == nil { receive(connection, buffered: buffer) }
            }
    }

    private func respond(_ command: String, to connection: NWConnection) {
        guard let tag = command.split(separator: " ").first else { return }
        let upper = command.uppercased()
        let ok = "\(tag) OK completed\r\n"
        if upper.contains(" CAPABILITY") {
            send("* CAPABILITY IMAP4rev1\r\n" + ok, to: connection)
        } else if upper.contains(" LOGIN ") {
            send(ok, to: connection)
        } else if upper.contains(" SELECT ") {
            send(
                "* FLAGS (\\Seen)\r\n* 1 EXISTS\r\n* 0 RECENT\r\n* OK [UIDVALIDITY 42] Validity\r\n" +
                    ok,
                to: connection
            )
        } else if upper.contains("ENVELOPE") {
            send(
                "* 1 FETCH (UID 1 ENVELOPE (NIL \"Outer message\" NIL NIL NIL NIL NIL NIL NIL NIL))\r\n" +
                    ok,
                to: connection
            )
        } else if upper.contains("BODYSTRUCTURE") {
            send("* 1 FETCH (UID 1 BODYSTRUCTURE \(structure))\r\n" + ok, to: connection)
        } else if let range = upper.range(
            of: #"BODY(?:\.PEEK)?\[([0-9.]+)\]"#,
            options: .regularExpression
        ) {
            let token = String(upper[range])
            let section = String(token.split(separator: "[")[1].dropLast())
            sections.append(section)
            guard let body = bodies[section] else {
                send("\(tag) NO Unexpected body section\r\n", to: connection)
                return
            }
            var response = Data("* 1 FETCH (UID 1 BODY[\(section)] {\(body.count)}\r\n".utf8)
            response.append(body)
            response.append(Data(")\r\n\(ok)".utf8))
            connection.send(content: response, completion: .contentProcessed { _ in })
        } else if upper.contains(" LOGOUT") {
            send("* BYE Closing\r\n" + ok, to: connection)
        } else {
            send("\(tag) BAD Unsupported fixture command\r\n", to: connection)
        }
    }

    private func send(_ response: String, to connection: NWConnection) {
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in })
    }
}
#endif
