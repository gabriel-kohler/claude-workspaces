import Foundation

/// A minimal HTTP/1.1 request, enough for MCP's streamable HTTP transport on localhost.
public struct HTTPRequest: Equatable, Sendable {
    public var method: String
    public var path: String
    /// Header names lowercased.
    public var headers: [String: String]
    public var body: Data
}

public enum HTTPParser {
    public enum Result: Equatable {
        /// A full request and how many bytes it used.
        case request(HTTPRequest, consumed: Int)
        case needMore
        case invalid
    }

    public static let maxBody = 8 * 1024 * 1024

    public static func parse(_ buffer: Data) -> Result {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            return buffer.count > 64 * 1024 ? .invalid : .needMore
        }
        guard let head = String(data: buffer[buffer.startIndex..<headerEnd.lowerBound], encoding: .utf8) else { return .invalid }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return .invalid }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        if headers["transfer-encoding"]?.lowercased().contains("chunked") == true { return .invalid }
        let length = Int(headers["content-length"] ?? "0") ?? -1
        guard length >= 0, length <= maxBody else { return .invalid }
        let bodyStart = headerEnd.upperBound
        guard buffer.distance(from: bodyStart, to: buffer.endIndex) >= length else { return .needMore }
        let body = Data(buffer[bodyStart..<buffer.index(bodyStart, offsetBy: length)])
        let consumed = buffer.distance(from: buffer.startIndex, to: bodyStart) + length
        return .request(HTTPRequest(method: String(requestLine[0]), path: String(requestLine[1]), headers: headers, body: body),
                        consumed: consumed)
    }

    public static func response(status: Int, reason: String, contentType: String? = nil, body: Data = Data()) -> Data {
        var head = "HTTP/1.1 \(status) \(reason)\r\nContent-Length: \(body.count)\r\n"
        if let contentType { head += "Content-Type: \(contentType)\r\n" }
        head += "\r\n"
        return Data(head.utf8) + body
    }
}
