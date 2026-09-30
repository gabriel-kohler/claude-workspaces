import Foundation
import WorkspacesCore

/// Listens on a unix socket for the hook and MCP helpers. One request and one reply per connection.
final class IPCServer {
    private let path: String
    private let handler: @MainActor (IPCRequest) -> IPCResponse
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?

    init(path: String, handler: @escaping @MainActor (IPCRequest) -> IPCResponse) {
        self.path = path
        self.handler = handler
    }

    func start() throws {
        unlink(path)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw IPCError.system("socket", errno) }
        var addr = try UnixSocket.address(for: path)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else { throw IPCError.system("bind", errno) }
        chmod(path, 0o600)
        guard listen(fd, 32) == 0 else { throw IPCError.system("listen", errno) }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .userInitiated))
        source.setEventHandler { [weak self] in self?.acceptClient() }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        if fd >= 0 { close(fd) }
        unlink(path)
    }

    private func acceptClient() {
        let client = accept(fd, nil, nil)
        guard client >= 0 else { return }
        DispatchQueue.global(qos: .userInitiated).async { [handler] in
            defer { close(client) }
            var tv = timeval(tv_sec: 5, tv_usec: 0)
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            var noSigPipe: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

            let response: IPCResponse
            if let line = UnixSocket.readLine(fd: client),
               let request = try? JSONDecoder().decode(IPCRequest.self, from: line) {
                response = DispatchQueue.main.sync { MainActor.assumeIsolated { handler(request) } }
            } else {
                response = IPCResponse(ok: false, text: "pedido inválido")
            }
            var data = (try? JSONEncoder().encode(response)) ?? Data()
            data.append(0x0A)
            _ = UnixSocket.writeAll(fd: client, data)
        }
    }
}
