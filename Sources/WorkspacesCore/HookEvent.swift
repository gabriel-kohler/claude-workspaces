import Foundation

/// What a Claude Code hook tells the app about a session.
public struct HookUpdate: Equatable, Sendable {
    public var status: SessionStatus?
    /// Shown under the session name, e.g. the permission Claude is asking for.
    public var message: String?
    public var claudeSessionId: String?
    public var cwd: String?
    /// True when the event starts a new task, so the old activity phrase no longer applies.
    public var clearsActivity: Bool
    /// A prompt was sent, so Claude now has a conversation it can resume.
    public var startsConversation: Bool

    public init(status: SessionStatus?, message: String? = nil, claudeSessionId: String? = nil,
                cwd: String? = nil, clearsActivity: Bool = false, startsConversation: Bool = false) {
        self.status = status
        self.message = message
        self.claudeSessionId = claudeSessionId
        self.cwd = cwd
        self.clearsActivity = clearsActivity
        self.startsConversation = startsConversation
    }
}

public enum HookEvent {
    /// The events the app subscribes to in the settings it passes to `claude --settings`.
    public static let subscribed = ["SessionStart", "UserPromptSubmit", "PostToolUse", "Notification", "Stop", "SessionEnd"]

    public static func update(from payload: JSONValue) -> HookUpdate? {
        guard let event = payload["hook_event_name"]?.stringValue else { return nil }
        let sessionId = payload["session_id"]?.stringValue
        let cwd = payload["cwd"]?.stringValue

        switch event {
        case "SessionStart":
            return HookUpdate(status: .idle, claudeSessionId: sessionId, cwd: cwd)
        case "UserPromptSubmit":
            return HookUpdate(status: .working, claudeSessionId: sessionId, cwd: cwd, clearsActivity: true, startsConversation: true)
        case "PostToolUse":
            // After a permission prompt is answered the tool runs, so this also clears "waiting".
            return HookUpdate(status: .working, claudeSessionId: sessionId, cwd: cwd)
        case "Notification":
            // Claude also notifies when a finished session has sat at its prompt for a while
            // ("idle_prompt"). That is not waiting for the person, so the state stays as it is.
            let type = payload["notification_type"]?.stringValue
            let message = payload["message"]?.stringValue
            let idleReminder = type == "idle_prompt"
                || (type == nil && message?.lowercased().contains("waiting for your input") == true)
            if idleReminder { return HookUpdate(status: nil, claudeSessionId: sessionId, cwd: cwd) }
            return HookUpdate(status: .waiting, message: message, claudeSessionId: sessionId, cwd: cwd)
        case "Stop":
            return HookUpdate(status: .done, claudeSessionId: sessionId, cwd: cwd)
        case "SessionEnd":
            return HookUpdate(status: .ended, claudeSessionId: sessionId, cwd: cwd)
        default:
            return HookUpdate(status: nil, claudeSessionId: sessionId, cwd: cwd)
        }
    }
}
