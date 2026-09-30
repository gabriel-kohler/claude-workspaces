import Foundation

public struct ToolDefinition: Sendable {
    public var name: String
    public var description: String
    public var inputSchema: JSONValue
}

public struct ToolResult: Equatable, Sendable {
    public var text: String
    public var isError: Bool

    public init(text: String, isError: Bool = false) {
        self.text = text
        self.isError = isError
    }
}

public enum WorkspaceTools {
    private static func schema(_ properties: [String: (String, String)], required: [String] = []) -> JSONValue {
        var props: [String: JSONValue] = [:]
        for (name, (type, description)) in properties {
            props[name] = .object(["type": .string(type), "description": .string(description)])
        }
        return .object([
            "type": .string("object"),
            "properties": .object(props),
            "required": .array(required.map { .string($0) }),
        ])
    }

    public static let all: [ToolDefinition] = [
        ToolDefinition(
            name: "list_sessions",
            description: "Lists the Claude Code sessions open in the Workspaces app, grouped by workspace and project, with each one's state and id. Use it before open_session or send_message.",
            inputSchema: schema(["all_workspaces": ("boolean", "Include every workspace, not only this session's.")])
        ),
        ToolDefinition(
            name: "set_status",
            description: "Tells the Workspaces app, in a few words, what this session is doing right now (for example \"running the tests\"). The phrase shows in the sidebar and the grid. Call it when you start a long step.",
            inputSchema: schema(["text": ("string", "Short phrase, in the language the person uses.")], required: ["text"])
        ),
        ToolDefinition(
            name: "open_session",
            description: "Opens a new Claude Code session in a project of the Workspaces app, optionally in a new git worktree and with a first prompt.",
            inputSchema: schema([
                "project": ("string", "Project name as list_sessions shows it."),
                "worktree": ("string", "Name for a new git worktree. Omit to follow the project's setting."),
                "prompt": ("string", "First message for the new session."),
            ], required: ["project"])
        ),
        ToolDefinition(
            name: "send_message",
            description: "Types a message into another session's prompt without pressing Enter, and marks that session so the person sees it. Use it to hand context to a sibling session.",
            inputSchema: schema([
                "session": ("string", "Target session id (or its prefix) from list_sessions."),
                "text": ("string", "The message."),
            ], required: ["session", "text"])
        ),
        ToolDefinition(
            name: "notify",
            description: "Sends a macOS notification asking for the person's attention, with a short message.",
            inputSchema: schema(["text": ("string", "What the person should look at.")], required: ["text"])
        ),
        ToolDefinition(
            name: "close_session",
            description: "Closes another session of the same workspace that has finished or is idle.",
            inputSchema: schema(["session": ("string", "Session id (or its prefix) from list_sessions.")], required: ["session"])
        ),
    ]
}

/// MCP over stdio (newline-delimited JSON-RPC). Transport-free so it can be tested.
public final class MCPServer {
    public static let supportedVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]

    private let enabledTools: () -> [String]?
    private let callTool: (String, JSONValue) -> ToolResult

    /// - Parameters:
    ///   - enabledTools: names the app allows now, or nil when the app is unreachable (all are listed).
    ///   - callTool: runs a tool.
    public init(enabledTools: @escaping () -> [String]?, callTool: @escaping (String, JSONValue) -> ToolResult) {
        self.enabledTools = enabledTools
        self.callTool = callTool
    }

    /// Handles one JSON-RPC message. Returns nil for notifications.
    public func handle(_ message: JSONValue) -> JSONValue? {
        guard let method = message["method"]?.stringValue else { return nil }
        guard let id = message["id"], id != .null else { return nil }
        let params = message["params"] ?? .object([:])

        switch method {
        case "initialize":
            let requested = params["protocolVersion"]?.stringValue ?? ""
            let version = Self.supportedVersions.contains(requested) ? requested : Self.supportedVersions[0]
            return result(id, .object([
                "protocolVersion": .string(version),
                "capabilities": .object(["tools": .object([:])]),
                "serverInfo": .object(["name": .string("workspaces"), "version": .string("0.1.0")]),
                "instructions": .string("This session runs inside the Workspaces app, next to other Claude Code sessions. Use set_status at the start of long steps; use list_sessions to see sibling sessions."),
            ]))
        case "ping":
            return result(id, .object([:]))
        case "tools/list":
            let enabled = enabledTools()
            let tools = WorkspaceTools.all
                .filter { enabled?.contains($0.name) ?? true }
                .map { JSONValue.object(["name": .string($0.name), "description": .string($0.description), "inputSchema": $0.inputSchema]) }
            return result(id, .object(["tools": .array(tools)]))
        case "tools/call":
            guard let name = params["name"]?.stringValue else {
                return error(id, code: -32602, message: "missing tool name")
            }
            guard WorkspaceTools.all.contains(where: { $0.name == name }) else {
                return error(id, code: -32602, message: "unknown tool: \(name)")
            }
            let outcome = callTool(name, params["arguments"] ?? .object([:]))
            return result(id, .object([
                "content": .array([.object(["type": .string("text"), "text": .string(outcome.text)])]),
                "isError": .bool(outcome.isError),
            ]))
        default:
            return error(id, code: -32601, message: "method not found: \(method)")
        }
    }

    private func result(_ id: JSONValue, _ value: JSONValue) -> JSONValue {
        .object(["jsonrpc": .string("2.0"), "id": id, "result": value])
    }

    private func error(_ id: JSONValue, code: Int, message: String) -> JSONValue {
        .object(["jsonrpc": .string("2.0"), "id": id, "error": .object(["code": .number(Double(code)), "message": .string(message)])])
    }
}
