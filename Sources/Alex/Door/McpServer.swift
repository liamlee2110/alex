import Foundation
import Network

/// The door's transport: a loopback HTTP listener speaking the Streamable
/// HTTP shape of MCP — each JSON-RPC message a POST to /mcp, answered with
/// plain JSON and the connection closed. Stateless on purpose: no sessions,
/// no server-initiated stream (a GET gets 405, which the spec allows), so
/// the whole protocol surface stays small enough to read. `McpRpc` owns what
/// the messages mean.
///
/// Ported whole from Donna (github.com/liamlee2110/donna,
/// Integrations/McpServer.swift) with the port changed. Off by default and
/// started from Settings; whether it is actually listening is a published
/// status the Settings page reads back — a server that failed to bind while
/// the toggle sits green would be a silent failure.
@MainActor
final class McpServer: ObservableObject {

    enum Status: Equatable {
        case off
        case serving
        case failed(String)
    }

    /// Fixed, because the vault's `.mcp.json` bakes the URL in — an
    /// ephemeral port would orphan every clone on relaunch. 53276 spells
    /// LEARN on a phone keypad.
    nonisolated static let port: UInt16 = 53276
    nonisolated static let endpoint = "http://127.0.0.1:53276/mcp"

    @Published private(set) var status: Status = .off

    private let rpc: McpRpc
    private var loop: Loop?

    init(rpc: McpRpc) {
        self.rpc = rpc
    }

    var isServing: Bool { status == .serving }

    func apply(enabled: Bool) {
        if enabled { start() } else { stop() }
    }

    private func start() {
        guard loop == nil else { return }
        let rpc = self.rpc
        let loop: Loop
        do {
            loop = try Loop(
                port: Self.port,
                respond: { body, done in
                    // Socket callbacks arrive on the loop's queue; the stores
                    // are main-actor. One hop in, one hop back.
                    Task { @MainActor in
                        done(rpc.respond(to: body))
                    }
                },
                state: { [weak self] status in
                    Task { @MainActor in self?.status = status }
                })
        } catch {
            status = .failed(error.localizedDescription)
            return
        }
        self.loop = loop
        loop.start()
    }

    private func stop() {
        loop?.stop()
        loop = nil
        status = .off
    }
}

/// The socket half, living entirely on its own queue — same shape as the
/// OAuth `LoopbackCatcher`, and the same load-bearing line:
/// `requiredLocalEndpoint` pins the listener to 127.0.0.1, because
/// `NWListener` otherwise listens on every interface and a task record
/// readable from the network is a door nobody meant to build.
private final class Loop: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.liamlee.alex.door")
    private let respond: @Sendable (Data, @escaping @Sendable (Data?) -> Void) -> Void
    private let state: @Sendable (McpServer.Status) -> Void

    private var connections: [ObjectIdentifier: NWConnection] = [:]

    init(port: UInt16,
         respond: @escaping @Sendable (Data, @escaping @Sendable (Data?) -> Void) -> Void,
         state: @escaping @Sendable (McpServer.Status) -> Void) throws {
        self.respond = respond
        self.state = state
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        listener = try NWListener(using: params)
    }

    func start() {
        listener.stateUpdateHandler = { [weak self] update in
            switch update {
            case .ready:
                self?.state(.serving)
            case .failed(let error):
                self?.state(.failed(error.localizedDescription))
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.queue.async { self?.accept(connection) }
        }
        listener.start(queue: queue)
    }

    func stop() {
        queue.async {
            self.listener.stateUpdateHandler = nil
            self.listener.cancel()
            self.connections.values.forEach { $0.cancel() }
            self.connections = [:]
        }
    }

    // MARK: - One HTTP exchange

    private func accept(_ connection: NWConnection) {
        connections[ObjectIdentifier(connection)] = connection
        connection.start(queue: queue)
        receive(on: connection, buffered: Data())
    }

    /// A request body can arrive across any number of TCP reads — the OAuth
    /// catcher's single receive is enough for a redirect's GET, but a JSON
    /// POST has to be reassembled until Content-Length is satisfied.
    private func receive(on connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffered
            if let data { buffer.append(data) }

            guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                if buffer.count > 64 * 1024 || isComplete || error != nil {
                    self.close(connection)
                } else {
                    self.receive(on: connection, buffered: buffer)
                }
                return
            }

            let head = String(decoding: buffer[..<headerEnd.lowerBound], as: UTF8.self)
            let lines = head.components(separatedBy: "\r\n")
            let request = lines.first?.components(separatedBy: " ") ?? []
            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                guard let colon = line.firstIndex(of: ":") else { continue }
                headers[line[..<colon].lowercased()] =
                    line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }

            let length = Int(headers["content-length"] ?? "0") ?? 0
            guard length <= 1024 * 1024 else {
                self.reply(connection, status: "413 Content Too Large", body: nil)
                return
            }
            let bodyStart = headerEnd.upperBound
            guard buffer.count - bodyStart >= length else {
                if isComplete || error != nil {
                    self.close(connection)
                } else {
                    self.receive(on: connection, buffered: buffer)
                }
                return
            }

            self.route(connection,
                       method: request.first ?? "",
                       path: request.count > 1 ? request[1] : "",
                       headers: headers,
                       body: buffer.subdata(in: bodyStart..<(bodyStart + length)))
        }
    }

    private func route(_ connection: NWConnection, method: String, path: String,
                       headers: [String: String], body: Data) {
        // A browser can be scripted into POSTing at 127.0.0.1 from any page it
        // has open — the DNS-rebinding trick the MCP spec's Origin check
        // exists for. Non-browser clients send no Origin and pass untouched.
        if let origin = headers["origin"],
           let host = URL(string: origin)?.host,
           !["127.0.0.1", "localhost", "::1"].contains(host) {
            reply(connection, status: "403 Forbidden", body: nil)
            return
        }
        guard path == "/mcp" || path.hasPrefix("/mcp?") else {
            reply(connection, status: "404 Not Found", body: nil)
            return
        }
        // GET is how a client asks for a server-initiated stream and DELETE
        // is how it ends a session; this server keeps neither, and 405 is the
        // spec's way to say so.
        guard method == "POST" else {
            reply(connection, status: "405 Method Not Allowed", body: nil,
                  extra: "Allow: POST\r\n")
            return
        }
        respond(body) { [weak self] answer in
            self?.queue.async {
                guard let self else { return }
                if let answer {
                    self.reply(connection, status: "200 OK", body: answer)
                } else {
                    self.reply(connection, status: "202 Accepted", body: nil)
                }
            }
        }
    }

    /// Every response closes the connection: one POST per TCP connection is
    /// slower than keep-alive by a millisecond nobody notices on loopback,
    /// and it keeps this file free of pipelining.
    private func reply(_ connection: NWConnection, status: String, body: Data?,
                       extra: String = "") {
        let payload = body ?? Data()
        var head = "HTTP/1.1 \(status)\r\n"
        if body != nil { head += "Content-Type: application/json\r\n" }
        head += extra
        head += "Content-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + payload,
                        completion: .contentProcessed { [weak self] _ in
            self?.close(connection)
        })
    }

    private func close(_ connection: NWConnection) {
        connection.cancel()
        connections[ObjectIdentifier(connection)] = nil
    }
}
