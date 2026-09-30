import Foundation
import WorkspacesCore

private var sessionFromEnvironment: String? {
    ProcessInfo.processInfo.environment[ClaudeLaunch.sessionEnvKey]
}

/// `Workspaces mcp`: stdio MCP server that forwards tool calls to the running app.
enum MCPBridge {
    static func run() {
        let session = sessionFromEnvironment
        let server = MCPServer(
            enabledTools: {
                (try? IPCClient.send(IPCRequest(kind: .tools, session: session), timeout: 2))?.enabledTools
            },
            callTool: { name, arguments in
                do {
                    let reply = try IPCClient.send(IPCRequest(kind: .tool, session: session, tool: name, arguments: arguments), timeout: 30)
                    return ToolResult(text: reply.text, isError: !reply.ok)
                } catch {
                    return ToolResult(text: "O app Workspaces não respondeu (\(error)). Ele precisa estar aberto.", isError: true)
                }
            }
        )
        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty, let message = JSONValue.parse(Data(line.utf8)) else { continue }
            if let reply = server.handle(message) {
                FileHandle.standardOutput.write(reply.encodedLine())
            }
        }
    }
}

/// `Workspaces hook`: reads the hook payload from stdin and tells the app. Never blocks Claude.
enum HookSender {
    static func run() {
        guard let session = sessionFromEnvironment else { return }
        let data = FileHandle.standardInput.readDataToEndOfFile()
        let payload = JSONValue.parse(data) ?? .null
        _ = try? IPCClient.send(IPCRequest(kind: .hook, session: session, payload: payload,
                                          launch: ProcessInfo.processInfo.environment[ClaudeLaunch.launchEnvKey]), timeout: 2)
    }
}
