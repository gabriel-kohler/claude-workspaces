import Foundation

public enum NewSessionMode: String, Codable, CaseIterable, Sendable {
    /// Runs in the project folder itself.
    case folder
    /// Asks Claude Code for a fresh git worktree (`claude -w`).
    case worktree
}

/// A session the app remembers so it can be resumed with `claude --resume`.
public struct SavedSession: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var label: String
    public var claudeSessionId: String?
    public var worktree: String?
    /// Last folder Claude reported; a worktree session must be resumed from there.
    public var cwd: String?

    public init(id: UUID, label: String, claudeSessionId: String? = nil, worktree: String? = nil, cwd: String? = nil) {
        self.id = id
        self.label = label
        self.claudeSessionId = claudeSessionId
        self.worktree = worktree
        self.cwd = cwd
    }
}

public struct Project: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var path: String
    public var newSessionMode: NewSessionMode
    public var sessionsOnOpen: Int
    /// Appended to every `claude` command of this project, as written (e.g. `--add-dir ../api`).
    public var claudeArguments: String
    public var savedSessions: [SavedSession]

    public init(id: UUID = UUID(), name: String, path: String, newSessionMode: NewSessionMode = .folder,
                sessionsOnOpen: Int = 1, claudeArguments: String = "", savedSessions: [SavedSession] = []) {
        self.id = id
        self.name = name
        self.path = path
        self.newSessionMode = newSessionMode
        self.sessionsOnOpen = sessionsOnOpen
        self.claudeArguments = claudeArguments
        self.savedSessions = savedSessions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        path = try c.decode(String.self, forKey: .path)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? URL(fileURLWithPath: path).lastPathComponent
        newSessionMode = try c.decodeIfPresent(NewSessionMode.self, forKey: .newSessionMode) ?? .folder
        sessionsOnOpen = try c.decodeIfPresent(Int.self, forKey: .sessionsOnOpen) ?? 1
        claudeArguments = try c.decodeIfPresent(String.self, forKey: .claudeArguments) ?? ""
        savedSessions = try c.decodeIfPresent([SavedSession].self, forKey: .savedSessions) ?? []
    }
}

public struct Workspace: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var projects: [Project]

    public init(id: UUID = UUID(), name: String, projects: [Project] = []) {
        self.id = id
        self.name = name
        self.projects = projects
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        projects = try c.decodeIfPresent([Project].self, forKey: .projects) ?? []
    }
}

public struct AppConfig: Codable, Equatable, Sendable {
    public var workspaces: [Workspace]
    public var notifyWhenWaiting: Bool
    public var reopenSessions: Bool
    public var disabledTools: [String]
    /// Command used to start Claude Code; resolved by the login shell, so `claude` is enough.
    public var claudeCommand: String
    /// Minutes before a quiet, hidden session is frozen (SIGSTOP); 0 turns it off.
    public var freezeAfterMinutes: Int
    /// Minutes before it is hibernated (process ended, resumed on open); 0 turns it off.
    public var hibernateAfterMinutes: Int

    public static let defaultDisabledTools = ["close_session"]

    public init(workspaces: [Workspace] = [], notifyWhenWaiting: Bool = true, reopenSessions: Bool = true,
                disabledTools: [String] = AppConfig.defaultDisabledTools, claudeCommand: String = "claude",
                freezeAfterMinutes: Int = 2, hibernateAfterMinutes: Int = 30) {
        self.workspaces = workspaces
        self.notifyWhenWaiting = notifyWhenWaiting
        self.reopenSessions = reopenSessions
        self.disabledTools = disabledTools
        self.claudeCommand = claudeCommand
        self.freezeAfterMinutes = freezeAfterMinutes
        self.hibernateAfterMinutes = hibernateAfterMinutes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workspaces = try c.decodeIfPresent([Workspace].self, forKey: .workspaces) ?? []
        notifyWhenWaiting = try c.decodeIfPresent(Bool.self, forKey: .notifyWhenWaiting) ?? true
        reopenSessions = try c.decodeIfPresent(Bool.self, forKey: .reopenSessions) ?? true
        disabledTools = try c.decodeIfPresent([String].self, forKey: .disabledTools) ?? AppConfig.defaultDisabledTools
        claudeCommand = try c.decodeIfPresent(String.self, forKey: .claudeCommand) ?? "claude"
        freezeAfterMinutes = try c.decodeIfPresent(Int.self, forKey: .freezeAfterMinutes) ?? 2
        hibernateAfterMinutes = try c.decodeIfPresent(Int.self, forKey: .hibernateAfterMinutes) ?? 30
    }
}

public enum SessionStatus: String, Codable, Sendable {
    case waiting, working, done, idle, ended

    public var label: String {
        switch self {
        case .waiting: return "Esperando você"
        case .working: return "Trabalhando"
        case .done: return "Concluído"
        case .idle: return "Parado"
        case .ended: return "Encerrada"
        }
    }

    /// Sort order in lists: what needs the person first.
    public var rank: Int {
        switch self {
        case .waiting: return 0
        case .working: return 1
        case .done: return 2
        case .idle: return 3
        case .ended: return 4
        }
    }
}
