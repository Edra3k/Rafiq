#if !APPSTORE
import Foundation

// MARK: - Answering a Claude Code session from Details (and from the iPhone)
//
// Continues that same conversation in the background: `claude -p <text> --resume <session>`,
// in the session's own folder, with the same editor routing so the hooks land on the same
// pill. The notch follows the new turn like any other, and every permission it asks for
// still waits on its card: nothing is approved here. The session and its folder come from
// what the hooks reported, never from the text. GitHub build only (the App Store build is
// sandboxed and can't start `claude`).

@MainActor
final class SessionReply: ObservableObject {
    static let shared = SessionReply()

    /// Sessions with a reply running, by session id.
    @Published private(set) var running: Set<String> = []
    private var processes: [String: Process] = [:]

    enum Outcome: Equatable { case started, empty, busy, noClaude, noFolder }

    static let maxLength = 8_000

    /// Why the last reply of a session ended badly, by session id (cleared by the next one).
    @Published private(set) var failures: [String: Failure] = [:]

    enum Failure: Equatable {
        /// `claude` isn't signed in: it has to be, once, in a terminal (/login).
        case notSignedIn
        case ended(String)
    }

    /// Claude Code sessions (in a terminal, VS Code, Cursor or the Claude app's Code tab).
    static func canReply(pill: String) -> Bool {
        ["integration_claude", "agent_cursor", "agent_claude-desktop"].contains(PillCatalog.basePillId(pill))
    }

    /// Stops a reply Rafiq is running for this session (only those: a turn started in a terminal
    /// or the Claude app belongs to it). The turn ends there in Details.
    func stop(sessionId: String) {
        guard let process = processes[sessionId] else { return }
        stopping.insert(sessionId)
        process.terminate()
        TurnHistory.shared.markStopped(session: sessionId)
    }
    private var stopping: Set<String> = []

    @discardableResult
    func send(_ text: String, sessionId: String, cwd: String, pillId: String,
              log: @escaping @MainActor (String) -> Void = { _ in }) -> Outcome {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= Self.maxLength else { return .empty }
        guard !running.contains(sessionId) else { log("a reply is already running for this session"); return .busy }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: cwd, isDirectory: &isDirectory), isDirectory.boolValue else {
            log("the session's folder is gone"); return .noFolder
        }
        guard let claude = AskRunner.claudeExecutable() else {
            log("can't find the claude command"); return .noClaude
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claude)
        process.arguments = ["-p", text, "--resume", sessionId]
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        env["PATH"] = [URL(fileURLWithPath: claude).deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin",
                       "/usr/bin", "/bin", "/usr/sbin", "/sbin", "\(home)/.local/bin", env["PATH"] ?? ""].joined(separator: ":")
        // The hooks route events by editor: keep them on the same pill.
        if PillCatalog.basePillId(pillId) == "agent_cursor" {
            env["__CFBundleIdentifier"] = "com.todesktop.230313mzl4w4u92"
        } else if PillCatalog.basePillId(pillId) == "agent_claude-desktop" {
            env["CLAUDE_CODE_ENTRYPOINT"] = "claude-desktop"   // nb-hook routes it to the Claude app's pill
        } else {
            env["TERM_PROGRAM"] = "vscode"
        }
        process.environment = env
        process.standardInput = FileHandle.nullDevice
        // Output to a file (a pipe could fill up and stall claude); its end is logged on failure.
        let logURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/NotchBuddy/reply-last.log")
        try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let output = try? FileHandle(forWritingTo: logURL)
        process.standardOutput = output ?? FileHandle.nullDevice
        process.standardError = output ?? FileHandle.nullDevice
        process.terminationHandler = { finished in
            try? output?.close()
            let data = (try? Data(contentsOf: logURL)) ?? Data()
            let tail = String(decoding: data.suffix(400), as: UTF8.self).replacingOccurrences(of: "\n", with: " ")
            let status = finished.terminationStatus
            Task { @MainActor in
                SessionReply.shared.running.remove(sessionId)
                SessionReply.shared.processes[sessionId] = nil
                let wasStopped = SessionReply.shared.stopping.remove(sessionId) != nil
                if status != 0 && !wasStopped {
                    let lower = tail.lowercased()
                    SessionReply.shared.failures[sessionId] = lower.contains("not logged in") || lower.contains("/login")
                        ? .notSignedIn
                        : .ended(String(tail.trimmingCharacters(in: .whitespaces).suffix(160)))
                }
                log(status == 0 ? "finished (\(sessionId.prefix(8)))" : "ended with \(status): \(tail)")
            }
        }
        do {
            try process.run()
            processes[sessionId] = process
            running.insert(sessionId)
            failures[sessionId] = nil
            log("running in \(URL(fileURLWithPath: cwd).lastPathComponent) (\(sessionId.prefix(8))): \(text.count) chars")
            return .started
        } catch {
            log("couldn't start claude: \(error.localizedDescription)")
            return .noClaude
        }
    }
}
#endif
