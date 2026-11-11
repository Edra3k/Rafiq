import Foundation

// MARK: - Git state of a session's project, for the open card
// Branch, commits not pushed yet, files changed: read with `git status --porcelain=v1 -b`
// in the session's folder, off the main thread, at most every 5 s per folder, when the
// agent's turn moves on (hook events) or the card opens. Local only: no fetch, no network.
// Parsing is pure: tested by scripts/test-git-status.sh.

struct GitSummary: Equatable, Sendable {
    var branch: String
    var ahead: Int
    var behind: Int
    var changed: Int

    /// `git status --porcelain=v1 -b` output → summary; nil if it is not a repository.
    static func parse(_ output: String) -> GitSummary? {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard let head = lines.first, head.hasPrefix("## ") else { return nil }
        var info = String(head.dropFirst(3))
        var ahead = 0, behind = 0
        if let open = info.range(of: " ["), info.hasSuffix("]") {
            let inside = info[open.upperBound..<info.index(before: info.endIndex)]
            for part in inside.split(separator: ",") {
                let words = part.trimmingCharacters(in: .whitespaces).split(separator: " ")
                guard words.count == 2, let n = Int(words[1]) else { continue }
                if words[0] == "ahead" { ahead = n }
                if words[0] == "behind" { behind = n }
            }
            info = String(info[..<open.lowerBound])
        }
        // "main...origin/main", "No commits yet on main", "HEAD (no branch)"
        var branch = info
        if let dots = branch.range(of: "...") { branch = String(branch[..<dots.lowerBound]) }
        if branch.hasPrefix("No commits yet on ") { branch = String(branch.dropFirst("No commits yet on ".count)) }
        if branch.hasPrefix("HEAD (no branch)") { branch = "HEAD" }
        return GitSummary(branch: branch, ahead: ahead, behind: behind, changed: lines.count - 1)
    }
}

@MainActor
final class GitStatusStore: ObservableObject {
    static let shared = GitStatusStore()

    @Published private(set) var summaries: [String: GitSummary] = [:]
    private var lastRun: [String: Date] = [:]
    private var running = Set<String>()

    func summary(for cwd: String?) -> GitSummary? {
        guard let cwd, !cwd.isEmpty else { return nil }
        return summaries[cwd]
    }

    /// Reads the folder's state again unless it was read in the last 5 s.
    func refresh(_ cwd: String?, force: Bool = false) {
        guard let cwd, !cwd.isEmpty, !running.contains(cwd) else { return }
        if !force, let last = lastRun[cwd], Date().timeIntervalSince(last) < 5 { return }
        lastRun[cwd] = Date()
        running.insert(cwd)
        Task.detached(priority: .utility) {
            let output = Self.run(cwd)
            let summary = output.flatMap(GitSummary.parse)
            await MainActor.run {
                let store = GitStatusStore.shared
                store.running.remove(cwd)
                if store.summaries[cwd] != summary { store.summaries[cwd] = summary }
            }
        }
    }

    nonisolated private static func run(_ cwd: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", cwd, "status", "--porcelain=v1", "-b", "--untracked-files=normal"]
        // Never ask for anything (credentials, pager): this is a read.
        p.environment = ["GIT_TERMINAL_PROMPT": "0", "GIT_OPTIONAL_LOCKS": "0", "PATH": "/usr/bin:/bin"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
