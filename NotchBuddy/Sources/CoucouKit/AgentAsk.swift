import Foundation

// MARK: - "Ask…": one place to hand a task to Hermes or Claude
//
// The same words come from the notch (typed or dictated), "Hey Rafiq", the iPhone or the
// Watch. The router is pure (Foundation only, scripts/test-agent-ask.sh tests it):
// - an agent named at the start ("ask Hermes to…", "dis à Claude de…") wins,
// - else Auto picks: the server, the home and the local models go to Hermes; code goes
//   to Claude; a plain question stays in the chat.
// Nothing here runs anything: the Mac's AskRunner does, and every dangerous command
// still waits for a click on the approval card.

enum AskTarget: String, Codable, CaseIterable, Sendable {
    case auto, hermes, claude, answer
}

struct AskRoute: Equatable, Sendable {
    /// Who does it (never `.auto`).
    var target: AskTarget
    /// The task, with "ask Hermes to" taken off.
    var text: String
    /// The user named the agent (or picked its chip): Auto didn't guess.
    var explicit: Bool
}

enum AskRouter {
    /// Where to send `raw`. `chosen` is the chip picked (`.auto` lets the words decide);
    /// `hasHermes` is false when Hermes isn't installed here nor on the server.
    static func route(_ raw: String, chosen: AskTarget = .auto, hasHermes: Bool = true) -> AskRoute {
        let (named, rest) = strippedAgent(raw)
        let text = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        if chosen != .auto {
            return AskRoute(target: fallback(chosen, hasHermes: hasHermes), text: text, explicit: true)
        }
        if let named {
            return AskRoute(target: fallback(named, hasHermes: hasHermes), text: text, explicit: true)
        }
        return AskRoute(target: guess(text, hasHermes: hasHermes), text: text, explicit: false)
    }

    private static func fallback(_ target: AskTarget, hasHermes: Bool) -> AskTarget {
        target == .hermes && !hasHermes ? .claude : target
    }

    // MARK: Named agent

    /// The phrases that name an agent, folded (no accents, lowercase). Longest first.
    private static let leads: [(String, AskTarget)] = {
        let verbs = ["demande a", "demandes a", "dis a", "dit a", "dites a", "ask", "tell", "pregunta a", "dile a",
                     "frag", "sag"]
        let names: [(String, AskTarget)] = [("hermes", .hermes), ("claude code", .claude), ("claude", .claude)]
        var all: [(String, AskTarget)] = []
        for (name, target) in names {
            for verb in verbs { all.append(("\(verb) \(name)", target)) }
            all.append((name, target))
        }
        return all.sorted { $0.0.count > $1.0.count }
    }()

    /// Joining words after the agent's name: "de", "d'", "to", "que", "de", "zu"…
    private static let joins = ["de ", "d'", "d’", "to ", "que ", "qu'", "qu’", "zu ", ": ", ", ", "- "]

    /// ("ask Hermes to check the disk") → (.hermes, "check the disk"). No agent named → (nil, raw).
    static func strippedAgent(_ raw: String) -> (AskTarget?, String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // "Hey Rafiq, …" / "Rafiq, …" in front of it.
        for wake in ["hey rafiq", "ok rafiq", "rafiq"] {
            let folded = fold(text)
            if folded.hasPrefix(wake) {
                text = String(text.dropFirst(wake.count)).trimmingCharacters(in: CharacterSet(charactersIn: " ,.:!"))
                break
            }
        }
        let folded = fold(text)
        for (lead, target) in leads where folded.hasPrefix(lead) {
            let next = folded.dropFirst(lead.count).first
            guard next == nil || next == " " || next == "," || next == ":" || next == "'" || next == "’" else { continue }
            var rest = String(text.dropFirst(lead.count)).trimmingCharacters(in: .whitespaces)
            let restFolded = fold(rest)
            for join in joins where restFolded.hasPrefix(join) {
                rest = String(rest.dropFirst(join.count))
                break
            }
            rest = rest.trimmingCharacters(in: CharacterSet(charactersIn: " ,:"))
            return (target, rest)
        }
        return (nil, text)
    }

    // MARK: Auto

    /// The home, the server and what runs on it: Hermes's ground.
    static let hermesWords = [
        "serveur", "server", "proxmox", "pve", "vm", "vms", "conteneur", "container", "docker", "lxc",
        "homelab", "nas", "disque", "disk", "stockage", "storage", "sauvegarde", "backup", "jellyfin",
        "plex", "home assistant", "domotique", "maison", "reseau", "network", "wifi", "routeur", "router",
        "telegram", "rappel", "reminder", "rappelle", "agenda", "calendrier", "calendar", "meteo", "weather",
        "gpu", "ollama", "qwen", "modele local", "local model", "cron", "tous les jours", "every day",
        "redemarre", "restart", "reboot", "allume", "eteins", "uptime", "ssh",
    ]

    /// Code and projects: Claude's ground.
    static let claudeWords = [
        "code", "build", "compile", "bug", "corrige", "fix", "commit", "push", "pull request", "pr",
        "test", "tests", "refactor", "refacto", "fonction", "function", "classe", "class", "swift",
        "python", "typescript", "javascript", "rust", "api", "repo", "projet", "project", "xcode",
        "crash", "erreur de compilation", "lint", "readme", "changelog", "release", "branche", "branch",
        "implemente", "implement", "ajoute une", "add a", "ecris", "write",
    ]

    /// A plain question nobody needs to act on.
    static let questionLeads = [
        "c'est quoi", "qu'est-ce", "quest-ce", "pourquoi", "comment ca", "explique", "que veut dire",
        "what is", "what's", "why", "explain", "who is", "qui est", "combien", "how much", "how many",
    ]

    /// The words of a task for an agent (the server, the home, code): "Hey Rafiq, check the
    /// server's disk" goes to Hermes even without naming him.
    static func hasTaskWords(_ text: String) -> Bool {
        let words = " " + fold(text)
            .map { $0.isLetter || $0.isNumber || $0 == "'" || $0 == "-" ? $0 : " " }
            .reduce(into: "") { $0.append($1) } + " "
        return (hermesWords + claudeWords).contains { words.contains(" \($0) ") }
    }

    /// What Auto picks for `text`.
    static func guess(_ text: String, hasHermes: Bool) -> AskTarget {
        let words = " " + fold(text)
            .map { $0.isLetter || $0.isNumber || $0 == "'" || $0 == "-" ? $0 : " " }
            .reduce(into: "") { $0.append($1) } + " "
        func hits(_ list: [String]) -> Int { list.filter { words.contains(" \($0) ") }.count }
        let h = hasHermes ? hits(hermesWords) : 0
        let c = hits(claudeWords)
        if h == 0 && c == 0 {
            let folded = fold(text)
            if folded.hasSuffix("?") || questionLeads.contains(where: { folded.hasPrefix($0) }) { return .answer }
            return hasHermes ? .hermes : .claude
        }
        return h > c ? .hermes : .claude
    }

    // MARK: Project

    /// The project named in `text`, among the folders Rafiq has seen ("fix the build of Rafiq"
    /// → ~/Rafiq). The longest name found wins; none → nil.
    static func project(in text: String, among folders: [String]) -> String? {
        let words = " " + fold(text).map { $0.isLetter || $0.isNumber ? $0 : " " }.reduce(into: "") { $0.append($1) } + " "
        var best: (path: String, length: Int)?
        for path in folders {
            let name = fold((path as NSString).lastPathComponent)
                .map { $0.isLetter || $0.isNumber ? $0 : " " }.reduce(into: "") { $0.append($1) }
                .trimmingCharacters(in: .whitespaces)
            guard name.count >= 2, words.contains(" \(name) ") else { continue }
            if best == nil || name.count > best!.length { best = (path, name.count) }
        }
        return best?.path
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

// MARK: - From the iPhone and the Watch

/// What the iPhone writes to iCloud for the Mac (the text is encrypted), and what the
/// Watch sends the iPhone.
enum AskRecord {
    static let recordType = "AgentAsk"
    static let textKey = "text"
    static let targetKey = "target"
    static let createdKey = "createdAt"
    static let deviceKey = "deviceName"
    /// Longest task taken (a Watch dictation is far shorter).
    static let maxLength = 4000
}

// MARK: - A task's progress and answer, for the iPhone and the Watch

/// What the Mac publishes (encrypted) for each task: the iPhone lists them, the Watch shows
/// the latest. Only the Mac writes it.
struct AskResult: Codable, Identifiable, Equatable, Sendable {
    enum State: String, Codable, Sendable { case running, done, failed, stopped }
    var id: String
    var target: AskTarget
    var text: String
    var place: String
    var state: State
    var answer: String
    var steps: [String]
    var startedAt: Date
    var endedAt: Date?

    static let recordType = "AskResult"
    static func recordName(for id: String) -> String { "ask-result-\(id)" }
    static func id(fromRecordName name: String) -> String? {
        name.hasPrefix("ask-result-") ? String(name.dropFirst("ask-result-".count)) : nil
    }

    var agentName: String { target == .hermes ? "Hermes" : "Claude Code" }
    var colorHex: String { target == .hermes ? "#C084FC" : "#D97757" }
}

// MARK: - Said aloud

/// The answer as Rafiq says it: no Markdown, no code blocks or links read out, the first
/// sentences only (a long report stays on the card).
enum AskSpeech {
    static func sentences(_ answer: String, max: Int = 4, maxLength: Int = 420) -> [String] {
        var text = answer
        // Code blocks and inline code: said as "code" would be noise; drop blocks, keep words.
        text = text.replacingOccurrences(of: "```[\\s\\S]*?```", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "`([^`]*)`", with: "$1", options: .regularExpression)
        // Links: their words, not the address.
        text = text.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: "https?://\\S+", with: "", options: .regularExpression)
        // Headings, bullets, emphasis, tables.
        text = text.replacingOccurrences(of: "(?m)^\\s*(#{1,6}|[-*+•]|\\d+[.)])\\s+", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "[*_~|>]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        var out: [String] = []
        var total = 0
        var current = ""
        for ch in text {
            current.append(ch)
            if ".!?…".contains(ch) {
                let s = current.trimmingCharacters(in: .whitespaces)
                if s.count > 1 { out.append(s); total += s.count }
                current = ""
                if out.count >= max || total >= maxLength { return out }
            }
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty && out.count < max && total < maxLength { out.append(String(rest.prefix(maxLength - total))) }
        return out
    }
}
