import Foundation

// MARK: - The last turns of each pill, for Details
//
// A turn starts with the prompt (UserPromptSubmit), collects each tool the agent ran
// (PreToolUse: its label, the whole command or file, the guard's rating, when), the files it
// changed, and ends with the agent's last message (Stop) and the model it used (read from the
// end of the transcript). Five turns per pill, kept in memory only: nothing is written to disk.
// Written by HookServer; read by SessionFullView.

@MainActor
final class TurnHistory: ObservableObject {
    static let shared = TurnHistory()

    struct Step: Identifiable, Equatable {
        let id = UUID()
        var tool: String
        var label: String
        /// The whole command, the file, the URL… shown when the step is opened.
        var detail: String
        var risk: CommandRisk
        var at: Date
    }

    struct FileChange: Identifiable, Equatable {
        var id: String { path }
        var path: String
        var added: Int
        var removed: Int
        /// The latest diff of this file in AppState.sessionDiffs, to open it.
        var diffId: Int
    }

    struct Turn: Identifiable, Equatable {
        let id = UUID()
        var pill: String
        var sessionId: String
        /// The session's name, as the pill shows it ("Rafiq", the project…).
        var title: String
        var cwd: String
        var prompt: String
        var answer: String = ""
        var model: String?
        var startedAt: Date
        var endedAt: Date?
        var steps: [Step] = []
        /// Diffs of the pill with a larger id belong to this turn.
        var diffBaseline: Int
        /// Frozen at the end of the turn; computed live while it runs.
        var files: [FileChange]? = nil
    }

    @Published private(set) var turns: [String: [Turn]] = [:]

    static let kept = 5
    static let maxText = 8_000
    static let maxDetail = 2_000
    static let maxSteps = 300

    func begin(pill: String, session: String, title: String, cwd: String, prompt: String) {
        let baseline = AppState.shared.sessionDiffs[pill]?.map(\.id).max() ?? -1
        var list = turns[pill] ?? []
        list.append(Turn(pill: pill, sessionId: session, title: title, cwd: cwd,
                         prompt: String(prompt.prefix(Self.maxText)),
                         startedAt: Date(), diffBaseline: baseline))
        if list.count > Self.kept { list.removeFirst(list.count - Self.kept) }
        turns[pill] = list
    }

    func step(pill: String, session: String, tool: String, input: [String: Any], label: String, risk: CommandRisk) {
        guard var list = turns[pill], let i = list.lastIndex(where: { $0.sessionId == session && $0.endedAt == nil }) else { return }
        guard list[i].steps.count < Self.maxSteps else { return }
        list[i].steps.append(Step(tool: tool, label: label.isEmpty ? tool : label,
                                  detail: String(Self.detail(tool: tool, input: input).prefix(Self.maxDetail)),
                                  risk: risk, at: Date()))
        turns[pill] = list
    }

    func end(pill: String, session: String, answer: String, transcript: String?) {
        guard var list = turns[pill], let i = list.lastIndex(where: { $0.sessionId == session && $0.endedAt == nil }) else { return }
        list[i].endedAt = Date()
        list[i].answer = String(answer.prefix(Self.maxText))
        list[i].files = files(of: list[i])
        turns[pill] = list
        guard let transcript, !transcript.isEmpty else { return }
        let turnId = list[i].id
        Task.detached(priority: .utility) {
            guard let model = Self.model(inTranscript: transcript) else { return }
            await MainActor.run {
                guard var l = TurnHistory.shared.turns[pill], let j = l.firstIndex(where: { $0.id == turnId }) else { return }
                l[j].model = model
                TurnHistory.shared.turns[pill] = l
            }
        }
    }

    /// The turns behind a task's pill (its own session pill first), oldest first.
    func turns(for task: AgentTask) -> [Turn] {
        if let own = turns[task.id], !own.isEmpty { return own }
        return turns[task.pill] ?? []
    }

    /// The files a turn changed: frozen once it ended, live while it runs.
    func files(of turn: Turn) -> [FileChange] {
        if let frozen = turn.files { return frozen }
        let diffs = (AppState.shared.sessionDiffs[turn.pill] ?? []).filter { $0.id > turn.diffBaseline }
        var out: [FileChange] = []
        for d in diffs {
            if let k = out.firstIndex(where: { $0.path == d.path }) {
                out[k].added += d.added; out[k].removed += d.removed; out[k].diffId = d.id
            } else {
                out.append(FileChange(path: d.path, added: d.added, removed: d.removed, diffId: d.id))
            }
        }
        return out
    }

    // MARK: Helpers

    /// What a step did, in full: the command, the file, the pattern, the URL.
    nonisolated static func detail(tool: String, input: [String: Any]) -> String {
        if let command = input["command"] as? String { return command }
        var parts: [String] = []
        for key in ["file_path", "path", "notebook_path", "pattern", "url", "query", "description", "prompt"] {
            if let v = input[key] as? String, !v.isEmpty { parts.append(v) }
        }
        return parts.isEmpty ? tool : parts.joined(separator: "\n")
    }

    /// The last model named in a Claude Code transcript (JSONL), read from its last 256 KB.
    nonisolated static func model(inTranscript path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > 262_144 ? size - 262_144 : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        guard let regex = try? NSRegularExpression(pattern: #""model"\s*:\s*"([A-Za-z0-9._\-\[\]]+)""#) else { return nil }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for m in matches.reversed() {
            guard let r = Range(m.range(at: 1), in: text) else { continue }
            let raw = String(text[r])
            if raw != "<synthetic>" { return prettyModel(raw) }
        }
        return nil
    }

    /// "claude-opus-5-5-20261001" → "Opus 5.5"; anything else as it is.
    nonisolated static func prettyModel(_ raw: String) -> String {
        var s = raw.lowercased()
        if s.hasPrefix("claude-") { s.removeFirst(7) } else { return raw }
        var words = s.split(separator: "-").map(String.init)
        if let last = words.last, last.count == 8, Int(last) != nil { words.removeLast() }   // date
        words.removeAll { $0.hasPrefix("[") }                                                // [1m]
        guard let family = words.first(where: { Int($0) == nil }) else { return raw }
        let numbers = words.filter { Int($0) != nil }
        return ([family.prefix(1).uppercased() + family.dropFirst()] + (numbers.isEmpty ? [] : [numbers.joined(separator: ".")]))
            .joined(separator: " ")
    }

    /// Reads (Read, Grep, Glob, LS) follow each other: shown as one line.
    nonisolated static func isRead(_ tool: String) -> Bool {
        ["Read", "Grep", "Glob", "LS", "NotebookRead"].contains(tool)
    }

    /// The SF Symbol of a tool.
    nonisolated static func symbol(_ tool: String) -> String {
        switch tool {
        case "Bash", "BashOutput", "KillShell": return "terminal"
        case "Edit", "MultiEdit", "Write", "NotebookEdit": return "pencil"
        case "Read", "NotebookRead": return "eye"
        case "Grep", "Glob", "LS": return "magnifyingglass"
        case "WebFetch", "WebSearch": return "globe"
        case "Task", "Agent": return "person.2"
        case "TodoWrite": return "checklist"
        default: return tool.hasPrefix("mcp__") ? "puzzlepiece.extension" : "circle"
        }
    }
}
