import Foundation
import Network
import WorkspacesCore

/// Answers MCP (streamable HTTP, JSON responses only) on 127.0.0.1, so no helper process
/// runs per session. Everything happens on the main queue; requests are tiny.
final class MCPHTTPServer {
    private var listener: NWListener?
    private let token: String
    private let handler: @MainActor (_ session: String?, _ message: JSONValue) -> JSONValue?
    private(set) var port: UInt16?

    init(token: String, handler: @escaping @MainActor (String?, JSONValue) -> JSONValue?) {
        self.token = token
        self.handler = handler
    }

    var url: String? { port.map { "http://127.0.0.1:\($0)/mcp" } }

    /// Calls `ready` once the port is known, or with false when the listener failed.
    func start(ready: @escaping @MainActor (Bool) -> Void) {
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
            parameters.acceptLocalOnly = true
            let listener = try NWListener(using: parameters)
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.port = listener.port?.rawValue
                    MainActor.assumeIsolated { ready(true) }
                case .failed:
                    MainActor.assumeIsolated { ready(false) }
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            DispatchQueue.main.async { MainActor.assumeIsolated { ready(false) } }
        }
    }

    func stop() { listener?.cancel() }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            while true {
                switch HTTPParser.parse(buffer) {
                case .request(let request, let consumed):
                    buffer = buffer.subdata(in: consumed..<buffer.count)
                    connection.send(content: self.respond(to: request), completion: .contentProcessed { _ in })
                    continue
                case .invalid:
                    connection.send(content: HTTPParser.response(status: 400, reason: "Bad Request"), completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                    return
                case .needMore:
                    break
                }
                break
            }
            if isComplete || error != nil { connection.cancel(); return }
            self.receive(on: connection, buffer: buffer)
        }
    }

    private func respond(to request: HTTPRequest) -> Data {
        guard request.path == "/mcp" || request.path.hasPrefix("/mcp?") else {
            return HTTPParser.response(status: 404, reason: "Not Found")
        }
        guard request.headers["authorization"] == "Bearer \(token)" else {
            return HTTPParser.response(status: 401, reason: "Unauthorized")
        }
        // No server-initiated stream: GET is not offered, which the spec allows.
        guard request.method == "POST" else { return HTTPParser.response(status: 405, reason: "Method Not Allowed") }
        guard let message = JSONValue.parse(request.body) else {
            return HTTPParser.response(status: 400, reason: "Bad Request")
        }
        let session = request.headers[ClaudeLaunch.sessionHeader.lowercased()]
        let reply = MainActor.assumeIsolated { handler(session, message) }
        guard let reply else { return HTTPParser.response(status: 202, reason: "Accepted") }
        var body = reply.encodedLine()
        body.removeLast()
        return HTTPParser.response(status: 200, reason: "OK", contentType: "application/json", body: body)
    }
}
