import Foundation

public enum ShellSupport {
    /// Splits a command line the way a POSIX shell would for plain words and quotes
    /// (no variables, globs or operators). Returns nil when it needs a real shell.
    public static func words(_ line: String) -> [String]? {
        var words: [String] = []
        var current = ""
        var inWord = false
        var quote: Character?
        var escaping = false
        var escapingInDoubleQuotes = false
        for ch in line {
            if escaping {
                current.append(ch)
                escaping = false
                inWord = true
                continue
            }
            if escapingInDoubleQuotes {
                // POSIX: inside double quotes a backslash only escapes $ ` " \ and newline.
                if !"$`\"\\\n".contains(ch) { current.append("\\") }
                current.append(ch)
                escapingInDoubleQuotes = false
                continue
            }
            if let q = quote {
                if ch == q { quote = nil }
                else if ch == "\\" && q == "\"" { escapingInDoubleQuotes = true }
                else if ch == "$" || ch == "`", q == "\"" { return nil }
                else { current.append(ch) }
                continue
            }
            switch ch {
            case "'", "\"":
                quote = ch
                inWord = true
            case "\\":
                escaping = true
            case " ", "\t", "\n":
                if inWord { words.append(current); current = ""; inWord = false }
            case "$", "`", "|", "&", ";", "<", ">", "(", ")", "*", "?", "[":
                // Expansion or an operator: leave it to a real shell.
                return nil
            case "~", "#":
                // Home expansion or a comment only at the start of a word.
                if !inWord { return nil }
                current.append(ch)
            default:
                current.append(ch)
                inWord = true
            }
        }
        if quote != nil || escaping || escapingInDoubleQuotes { return nil }
        if inWord { words.append(current) }
        return words
    }

    /// Parses `env -0` output.
    public static func parseEnvironment(_ data: Data) -> [String: String] {
        var env: [String: String] = [:]
        for chunk in data.split(separator: 0) {
            guard let entry = String(data: Data(chunk), encoding: .utf8), let eq = entry.firstIndex(of: "=") else { continue }
            env[String(entry[..<eq])] = String(entry[entry.index(after: eq)...])
        }
        return env
    }

    /// Finds an executable by name in a PATH value. A name with a slash is taken as a path.
    public static func resolve(_ name: String, path: String?, isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        if name.contains("/") { return isExecutable(name) ? name : nil }
        for dir in (path ?? "").split(separator: ":") where !dir.isEmpty {
            let candidate = "\(dir)/\(name)"
            if isExecutable(candidate) { return candidate }
        }
        return nil
    }
}
