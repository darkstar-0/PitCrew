import Foundation
import Network

/// One HTTP request from a hook script.
struct IncomingRequest {
    let path: String
    let json: [String: Any]
    let raw: Data
    /// Sends the HTTP response body. `/event` requests are answered right away;
    /// `/permission` requests are held open until you click Allow / Deny / In VS Code.
    let reply: (Data) -> Void
}

/// Minimal HTTP server on 127.0.0.1.
///   POST /event       fire-and-forget hook events (answered immediately)
///   POST /permission  PermissionRequest hook; held open until a decision is made
final class EventServer {
    typealias Handler = (IncomingRequest) -> Void

    private let listener: NWListener
    private let queue = DispatchQueue(label: "pit-crew.server")
    private let handler: Handler

    init(port: UInt16, handler: @escaping Handler) throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        // Bind to loopback only: nothing off this machine can talk to Pit Crew.
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1",
                                                 port: NWEndpoint.Port(rawValue: port)!)
        listener = try NWListener(using: params)
        self.handler = handler
    }

    func start() {
        listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                NSLog("Pit Crew: server failed: \(error)")
            }
        }
        listener.start(queue: queue)
    }

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }

            if let parsed = Self.parse(buf) {
                self.dispatch(conn, path: parsed.path, body: parsed.body)
                return
            }
            if isComplete || error != nil {
                conn.cancel()
                return
            }
            self.receive(conn, buffer: buf)
        }
    }

    private func dispatch(_ conn: NWConnection, path: String, body: Data) {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]

        if path == "/permission", let json {
            let reply: (Data) -> Void = { [weak self] data in
                self?.queue.async { self?.send(conn, body: data) }
            }
            DispatchQueue.main.async {
                self.handler(IncomingRequest(path: path, json: json, raw: body, reply: reply))
            }
            return
        }

        send(conn, body: Data())
        if let json {
            DispatchQueue.main.async {
                self.handler(IncomingRequest(path: path, json: json, raw: body, reply: { _ in }))
            }
        }
    }

    /// Returns path + body once headers and Content-Length bytes have all arrived.
    private static func parse(_ buf: Data) -> (path: String, body: Data)? {
        guard let sep = buf.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let header = String(decoding: buf[buf.startIndex..<sep.lowerBound], as: UTF8.self)
        let lines = header.components(separatedBy: "\r\n")
        let requestLine = lines.first?.split(separator: " ") ?? []
        let path = requestLine.count > 1 ? String(requestLine[1]) : "/"

        var length = 0
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].lowercased() == "content-length" {
                length = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        let body = buf[sep.upperBound...]
        guard body.count >= length else { return nil }
        return (path, Data(body.prefix(length)))
    }

    private func send(_ conn: NWConnection, body: Data) {
        var response = Data(("HTTP/1.1 200 OK\r\n" +
                             "Content-Type: application/json\r\n" +
                             "Content-Length: \(body.count)\r\n" +
                             "Connection: close\r\n\r\n").utf8)
        response.append(body)
        conn.send(content: response, completion: .contentProcessed { _ in conn.cancel() })
    }
}
