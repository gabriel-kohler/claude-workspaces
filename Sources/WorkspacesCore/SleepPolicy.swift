import Foundation

public enum SleepState: String, Codable, Sendable {
    /// Process running normally.
    case awake
    /// Process stopped with SIGSTOP: no CPU, memory compressible, wakes instantly.
    case frozen
    /// Process ended; the conversation is resumed with `claude --resume` when opened.
    case hibernated
}

public enum SleepAction: Equatable, Sendable {
    case none, freeze, hibernate
}

/// Decides when a session that nobody is looking at can rest. Pure, so it can be tested.
public struct SleepPolicy: Sendable {
    /// Minutes of quiet before freezing; 0 turns it off.
    public var freezeAfterMinutes: Int
    /// Minutes of quiet before hibernating; 0 turns it off.
    public var hibernateAfterMinutes: Int

    public init(freezeAfterMinutes: Int, hibernateAfterMinutes: Int) {
        self.freezeAfterMinutes = freezeAfterMinutes
        self.hibernateAfterMinutes = hibernateAfterMinutes
    }

    public struct Session: Sendable {
        public var status: SessionStatus
        public var attention: Bool
        public var visible: Bool
        public var quietFor: TimeInterval
        public var state: SleepState
        public var hasConversation: Bool
        /// A shell under Claude means a command is running (a background task, a dev server).
        public var runningCommand: Bool

        public init(status: SessionStatus, attention: Bool, visible: Bool, quietFor: TimeInterval, state: SleepState,
                    hasConversation: Bool, runningCommand: Bool) {
            self.status = status
            self.attention = attention
            self.visible = visible
            self.quietFor = quietFor
            self.state = state
            self.hasConversation = hasConversation
            self.runningCommand = runningCommand
        }
    }

    public func action(for s: Session) -> SleepAction {
        // Only sessions that finished or sit at the prompt; never one that waits for the person.
        guard s.status == .done || s.status == .idle, !s.attention, !s.visible, !s.runningCommand,
              s.state != .hibernated else { return .none }
        // Without a conversation there is nothing to resume, so it may only freeze.
        if hibernateAfterMinutes > 0, s.hasConversation, s.quietFor >= Double(hibernateAfterMinutes) * 60 {
            return .hibernate
        }
        if freezeAfterMinutes > 0, s.state == .awake, s.quietFor >= Double(freezeAfterMinutes) * 60 {
            return .freeze
        }
        return .none
    }
}
