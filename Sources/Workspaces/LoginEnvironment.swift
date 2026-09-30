import Foundation
import WorkspacesCore

/// The environment of the person's login shell, read once so sessions start Claude directly
/// instead of paying for `zsh -l -i` (measured at 2.1 to 2.8 s) every time.
enum LoginEnvironment {
    private static let marker = "__WORKSPACES_ENV__"

    /// Keys that belong to whoever launched the app, not to a new session.
    private static func inherited(_ key: String) -> Bool {
        key == "CLAUDECODE" || key.hasPrefix("CLAUDE_CODE_") || key.hasPrefix("__CF") ||
            ["TERM_SESSION_ID", "TERM_PROGRAM", "TERM_PROGRAM_VERSION", "SHLVL", "PWD", "OLDPWD", "_",
             ClaudeLaunch.sessionEnvKey].contains(key)
    }

    /// Runs off the main thread. Falls back to the app's own environment on failure.
    static func capture(completion: @escaping @MainActor ([String: String]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = read() ?? ProcessInfo.processInfo.environment
            let cleaned = result.filter { !inherited($0.key) }
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(cleaned) } }
        }
    }

    private static func read() -> [String: String]? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        // The marker separates whatever the rc files print from the real env output.
        process.arguments = ["-l", "-i", "-c", "printf '\\0\(marker)\\0'; /usr/bin/env -0"]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        do { try process.run() } catch { return nil }

        let deadline = DispatchTime.now() + 15
        let done = DispatchSemaphore(value: 0)
        var data = Data()
        DispatchQueue.global().async {
            data = pipe.fileHandleForReading.readDataToEndOfFile()
            done.signal()
        }
        if done.wait(timeout: deadline) == .timedOut {
            process.terminate()
            return nil
        }
        process.waitUntilExit()
        guard let range = data.range(of: Data("\0\(marker)\0".utf8)) else { return nil }
        let env = ShellSupport.parseEnvironment(data.subdata(in: range.upperBound..<data.count))
        return env["PATH"] == nil ? nil : env
    }
}
