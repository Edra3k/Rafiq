#if !APPSTORE
import AppKit
import NaturalLanguage
import SwiftUI

// MARK: - "Ask…": hand a task to Hermes or Claude, from the notch, the voice or the iPhone
//
// AskRouter (CoucouKit) picks who; this runs it in the background, no terminal window:
// - Hermes: `hermes chat -q <task>` on this Mac, or on the server through SSH. It needs a
//   terminal to ask for approvals (a run without one is "single query" and Hermes refuses
//   every dangerous command on its own), so it gets a pseudo-terminal. Each task runs in its
//   own folder (…/Ask/ask-xxxxxxxx): the hooks carry that folder (cwd), which is how its
//   steps and its answer find their way back here. Approvals reach the notch through the
//   Rafiq plugin's approval transport, like any Hermes session.
// - Claude: `claude -p <task>` in the project the task names (or the one chosen), with the
//   user's hooks: the notch follows it and every permission waits for a click.
// - A plain question goes to the chat.
// Nothing is approved here: a dangerous command still waits for the approval card.

@MainActor
final class AskRunner: ObservableObject {
    static let shared = AskRunner()

    struct Job: Identifiable, Equatable {
        enum State: Equatable { case running, done, failed(String), stopped }
        let id: String
        let target: AskTarget
        let text: String
        /// "Mac", the server's host, or the project's name.
        let place: String
        let startedAt: Date
        var state: State = .running
        var steps: [String] = []
        var answer = ""
        var endedAt: Date?
        /// Where it came from ("iPhone de …", "voice"), for the log.
        var source: String
    }

    /// Newest first; finished ones are kept for the session (at most 12).
    @Published private(set) var jobs: [Job] = [] {
        didSet {
            #if PHONE_LINK
            AskPublisher.shared.publish(jobs)
            #endif
        }
    }
    /// The job the `.ask` card shows; nil = the composer.
    @Published var shown: String?

    static let whereKey = "askHermesWhere"   // "auto" (default), "mac", "server"
    /// Rafiq says the answer aloud when a task ends (default on), like a voice assistant.
    static let speakKey = "askSpeakAnswers"
    static var speaksAnswers: Bool { UserDefaults.standard.object(forKey: speakKey) as? Bool ?? true }

    private var processes: [String: Process] = [:]
    /// What we type to Hermes (its terminal): "/exit" once it answered.
    private var inputs: [String: FileHandle] = [:]
    private var outputs: [String: Data] = [:]

    var shownJob: Job? { shown.flatMap { id in jobs.first { $0.id == id } } }

    /// Two jobs on the same question, side by side on the card ("Both").
    struct Comparison: Equatable { var hermes: String; var claude: String }
    @Published var comparison: Comparison?
    /// A file dropped on the island for Claude (a capture…), shown on the composer until sent.
    @Published var attachment: URL?

    /// The same question to Hermes and to Claude. One of them alone when the other can't run.
    @discardableResult
    func compare(_ raw: String, project: String?, source: String = "notch") -> Outcome {
        guard running.count <= 1 else { return .busy }
        let h = hasHermes ? ask(raw, chosen: .hermes, source: source) : .noHermes
        let c = ask(raw, chosen: .claude, project: project, source: source)
        switch (h, c) {
        case (.started(let a), .started(let b)):
            comparison = Comparison(hermes: a, claude: b)
            shown = nil
            return h
        case (.started, _): return h
        default: return c
        }
    }

    /// "Keep" on one side: that answer alone on the card.
    func keep(_ id: String) {
        comparison = nil
        shown = id
    }
    var running: [Job] { jobs.filter { $0.state == .running } }

    // MARK: Where Hermes is

    /// Hermes on this Mac.
    var hermesOnMac: String? { HookServer.hermesExecutablePath() }
    /// The server reached through Rafiq's SSH link (Settings → Home server).
    var serverHost: String? {
        let host = ServerLink.host
        return host.isEmpty || !ServerLink.tunnelEnabled ? nil : host
    }
    var hasHermes: Bool { hermesOnMac != nil || serverHost != nil }

    /// The server when the task is about it (or Hermes is only there), else this Mac.
    func hermesPlace(for text: String) -> String? {
        let pref = UserDefaults.standard.string(forKey: Self.whereKey) ?? "auto"
        switch pref {
        case "mac": return hermesOnMac != nil ? "Mac" : serverHost
        case "server": return serverHost ?? (hermesOnMac != nil ? "Mac" : nil)
        default:
            guard let server = serverHost else { return hermesOnMac != nil ? "Mac" : nil }
            if hermesOnMac == nil { return server }
            let folded = " " + AskRouter.fold(text) + " "
            let aboutServer = ["serveur", "server", "proxmox", "pve", "vm", "homelab", "nas", "jellyfin", "lxc", "conteneur", "container"]
                .contains { folded.contains(" \($0) ") || folded.contains(" \($0)s ") }
            return aboutServer ? server : "Mac"
        }
    }

    // MARK: Asking

    enum Outcome: Equatable { case started(String), chat, needsProject, noHermes, empty, busy }

    /// Routes and starts `raw`. `project` is the folder picked on the card for Claude.
    @discardableResult
    func ask(_ raw: String, chosen: AskTarget = .auto, project: String? = nil, source: String = "notch") -> Outcome {
        let route = AskRouter.route(raw, chosen: chosen, hasHermes: hasHermes)
        guard !route.text.isEmpty, route.text.count <= AskRecord.maxLength else { return .empty }
        guard running.count < 3 else { return .busy }
        switch route.target {
        case .answer, .auto:
            openChat(route.text)
            return .chat
        case .hermes:
            guard let place = hermesPlace(for: route.text) else { return .noHermes }
            return startHermes(route.text, place: place, source: source)
        case .claude:
            let folders = SessionLauncher.shared.projects
            guard let folder = AskRouter.project(in: route.text, among: folders) ?? project ?? SessionLauncher.shared.folder,
                  FileManager.default.fileExists(atPath: folder) else { return .needsProject }
            return startClaude(route.text, folder: folder, source: source)
        }
    }

    private func openChat(_ text: String) {
        let state = AppState.shared
        state.chatHistory.append(ChatMessage(role: .user, content: text))
        state.stateOverride = .thinking
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { state.view = .prompt }
        Task { await ClaudeService.shared.chat(query: text, context: nil, state: state) }
    }

    private static func newId() -> String {
        "ask-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).lowercased()
    }

    private func add(_ job: Job) {
        jobs.insert(job, at: 0)
        if jobs.count > 12 { jobs.removeLast(jobs.count - 12) }
        shown = job.id
        log("\(job.id) → \(job.target.rawValue) on \(job.place) from \(job.source): \(job.text.count) chars")
    }

    // MARK: Hermes

    private func startHermes(_ text: String, place: String, source: String) -> Outcome {
        let id = Self.newId()
        let process = Process()
        var env = Self.baseEnvironment()
        env["TERM"] = "xterm-256color"
        env["COLUMNS"] = "120"
        env["LINES"] = "40"
        if place == "Mac" {
            guard let hermes = hermesOnMac else { return .noHermes }
            let dir = Self.askFolder.appendingPathComponent(id, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            // script(1) gives Hermes a real terminal (a controlling one): it asks for
            // approvals there, so through Rafiq's transport, instead of refusing them.
            process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
            process.arguments = ["-q", "/dev/null", hermes, "chat", "-q", text]
            process.currentDirectoryURL = dir
        } else {
            // The server: a terminal there too (-tt), its own folder, then Hermes.
            let quoted = "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
            let remote = "mkdir -p ~/.coucou/ask/\(id) && cd ~/.coucou/ask/\(id) && PATH=\"$HOME/.local/bin:$PATH\" exec hermes chat -q \(quoted)"
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            process.arguments = ServerLink.sshArgs(place, ["-tt"]) + [remote]
        }
        process.environment = env

        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            Task { @MainActor in AskRunner.shared.appendOutput(id, data) }
        }
        process.terminationHandler = { finished in
            let status = finished.terminationStatus
            Task { @MainActor in AskRunner.shared.ended(id, status: status) }
        }
        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            log("\(id): couldn't start Hermes: \(error.localizedDescription)")
            return .noHermes
        }
        processes[id] = process
        inputs[id] = input.fileHandleForWriting
        add(Job(id: id, target: .hermes, text: text, place: place, startedAt: Date(), source: source))
        return .started(id)
    }

    private func appendOutput(_ id: String, _ data: Data) {
        var d = outputs[id] ?? Data()
        d.append(data)
        if d.count > 16_000 { d = d.suffix(16_000) }
        outputs[id] = d
    }

    // MARK: Claude

    private func startClaude(_ text: String, folder: String, source: String) -> Outcome {
        guard let claude = Self.claudeExecutable() else { return .needsProject }
        let id = Self.newId()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: claude)
        process.arguments = ["-p", text]
        process.currentDirectoryURL = URL(fileURLWithPath: folder)
        var env = Self.baseEnvironment(adding: URL(fileURLWithPath: claude).deletingLastPathComponent().path)
        env["TERM_PROGRAM"] = "vscode"   // the hooks keep it on the Claude pill
        process.environment = env
        process.standardInput = FileHandle.nullDevice
        let out = Pipe()
        process.standardOutput = out
        process.standardError = out
        out.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            Task { @MainActor in AskRunner.shared.appendOutput(id, data) }
        }
        process.terminationHandler = { finished in
            let status = finished.terminationStatus
            Task { @MainActor in
                // Let the last bytes land before reading the answer.
                try? await Task.sleep(for: .milliseconds(300))
                AskRunner.shared.ended(id, status: status)
            }
        }
        do { try process.run() } catch {
            log("\(id): couldn't start claude: \(error.localizedDescription)")
            return .needsProject
        }
        processes[id] = process
        add(Job(id: id, target: .claude, text: text, place: SessionLauncher.name(of: folder), startedAt: Date(), source: source))
        return .started(id)
    }

    // MARK: From the hooks

    /// Hermes sessions bound to their task, by Hermes's session id.
    private var sessionJobs: [String: String] = [:]

    /// A task's events: by its folder (the hook's cwd), else by the session bound at its start.
    private func jobId(session: String, cwd: String) -> String? {
        let last = (cwd as NSString).lastPathComponent
        if last.hasPrefix("ask-"), jobs.contains(where: { $0.id == last && $0.state == .running }) { return last }
        guard let id = sessionJobs[session], jobs.contains(where: { $0.id == id && $0.state == .running }) else { return nil }
        return id
    }

    /// A Hermes session started. Through Hermes's local gateway the hook's folder is the
    /// gateway's, not the task's: the one Hermes task started in the last minute that has no
    /// session yet is this one.
    func noteStart(session: String, agent: String, cwd: String) {
        guard agent == "hermes", sessionJobs[session] == nil else { return }
        let last = (cwd as NSString).lastPathComponent
        if last.hasPrefix("ask-"), jobs.contains(where: { $0.id == last }) { sessionJobs[session] = last; return }
        let bound = Set(sessionJobs.values)
        let waiting = jobs.filter { $0.target == .hermes && $0.state == .running && !bound.contains($0.id)
            && Date().timeIntervalSince($0.startedAt) < 90 }
        guard waiting.count == 1, let job = waiting.first else { return }
        sessionJobs[session] = job.id
        log("\(job.id) is Hermes session \(session.prefix(10))")
    }

    func noteStep(session: String, cwd: String, label: String) {
        guard let id = jobId(session: session, cwd: cwd), let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[i].steps.append(label)
        if jobs[i].steps.count > 30 { jobs[i].steps.removeFirst() }
    }

    /// Hermes finished its turn: keep the answer, close the session.
    func noteStop(session: String, cwd: String, answer: String) {
        if !running.isEmpty && jobId(session: session, cwd: cwd) == nil {
            log("a turn ended outside the tasks (\(session.prefix(10)), \((cwd as NSString).lastPathComponent))")
        }
        guard let id = jobId(session: session, cwd: cwd), let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[i].answer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        finish(id, state: .done)
        if let input = inputs[id] {
            try? input.write(contentsOf: Data("/exit\r".utf8))
        }
        let process = processes[id]
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if process?.isRunning == true { process?.terminate() }
        }
    }

    private func ended(_ id: String, status: Int32) {
        processes[id] = nil
        try? inputs[id]?.close()
        inputs[id] = nil
        let output = outputs.removeValue(forKey: id) ?? Data()
        guard let i = jobs.firstIndex(where: { $0.id == id }), jobs[i].state == .running else { return }
        let text = Self.plain(output)
        if jobs[i].target == .claude && status == 0 {
            jobs[i].answer = text
            finish(id, state: .done)
        } else {
            let tail = text.split(separator: "\n").suffix(3).joined(separator: " ")
            finish(id, state: .failed(tail.isEmpty ? "exit \(status)" : String(tail.suffix(240))))
        }
    }

    private func finish(_ id: String, state: Job.State) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[i].state = state
        jobs[i].endedAt = Date()
        log("\(id) \(state == .done ? "done" : "ended: \(state)")")
        guard state != .stopped else { return }
        shown = id
        speakEnd(of: jobs[i])
        // After the "finished" alert of the same turn, the answer comes up.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let app = AppState.shared
            guard app.pendingApproval == nil, app.pendingQuestion == nil else { return }
            if app.mode != .expanded {
                NotificationCenter.default.post(name: .hookExpand, object: IslandView.ask)
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { app.view = .ask }
            }
        }
    }

    // MARK: Aloud

    /// The answer, said: a task asked by voice always, else when "Answer aloud" is on.
    private func speakEnd(of job: Job) {
        guard Self.speaksAnswers || job.source == "voice" else { return }
        switch job.state {
        case .done:
            let sentences = AskSpeech.sentences(job.answer)
            guard !sentences.isEmpty else { return }
            say(sentences)
        case .failed:
            say([String(format: String(localized: "ask.said.failed %@", defaultValue: "%@ couldn't finish."), job.target == .hermes ? "Hermes" : "Claude")])
        default:
            break
        }
    }

    /// An approval is waiting for a task: said once, so it is heard from across the room.
    func noteApproval(session: String, cwd: String) {
        guard let id = jobId(session: session, cwd: cwd), let job = jobs.first(where: { $0.id == id }),
              Self.speaksAnswers || job.source == "voice" else { return }
        say([String(format: String(localized: "ask.said.approval %@", defaultValue: "%@ needs your OK in the notch."),
                    job.target == .hermes ? "Hermes" : "Claude")])
    }

    func readAloud(_ job: Job) {
        readAloud(text: job.answer)
    }

    /// Any answer, said aloud in its own language (Details' "Read aloud").
    func readAloud(text: String) {
        say(AskSpeech.sentences(text, max: 12, maxLength: 1500))
    }

    private func say(_ sentences: [String]) {
        let joined = sentences.joined(separator: " ")
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(joined)
        let locale = recognizer.dominantLanguage.map { Locale(identifier: $0.rawValue) }
        VoiceSpeaker.shared.say(sentences, locale: locale)
    }

    func stop(_ id: String) {
        guard let process = processes[id] else { return }
        finish(id, state: .stopped)
        if let input = inputs[id] { try? input.write(contentsOf: Data([0x03])) }
        process.terminate()
    }

    /// Hand the task (and Hermes's answer) to Claude.
    func passToClaude(_ job: Job) -> Outcome {
        let task = job.answer.isEmpty ? job.text
            : job.text + "\n\n" + String(localized: "ask.hermes-said", defaultValue: "Hermes found:") + "\n" + job.answer
        return ask(task, chosen: .claude, source: "hermes")
    }

    #if DEBUG
    /// Debug builds only: `scripts/ask-debug.sh "task" [hermes|claude]` asks as if typed in the
    /// card (UI automation can't type into the island's field reliably).
    private static var debugHook: NSObjectProtocol?
    static func installDebugHook() {
        guard debugHook == nil else { return }
        debugHook = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.edra3k.rafiq.debug.ask"), object: nil, queue: .main) { note in
            let text = note.object as? String ?? ""
            let target = AskTarget(rawValue: note.userInfo?["target"] as? String ?? "") ?? .auto
            MainActor.assumeIsolated {
                let outcome = AskRunner.shared.ask(text, chosen: target, source: "debug")
                AskRunner.shared.log("debug ask: \(outcome)")
                NotificationCenter.default.post(name: .hookExpand, object: IslandView.ask)
            }
        }
        // scripts/details-debug.sh: Details of a pill (object: its id, default the Claude app's).
        detailsHook = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.edra3k.rafiq.debug.details"), object: nil, queue: .main) { note in
            let pill = note.object as? String ?? "agent_claude-desktop"
            MainActor.assumeIsolated {
                guard let task = AppState.shared.tasks.first(where: { $0.pill == pill }) else { return }
                AppState.shared.focusId = task.id
                NotificationCenter.default.post(name: .hookExpand, object: IslandView.session)
            }
        }
    }
    private static var detailsHook: NSObjectProtocol?
    #endif

    // MARK: Helpers

    /// Where `claude` usually lives; the app doesn't get the shell's PATH.
    static func claudeExecutable() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.claude/local/claude", "\(home)/.local/bin/claude", "/opt/homebrew/bin/claude",
                "/usr/local/bin/claude", "\(home)/.npm-global/bin/claude", "\(home)/.bun/bin/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var askFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NotchBuddy/Ask", isDirectory: true)
    }

    private static func baseEnvironment(adding dir: String? = nil) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        env["PATH"] = ([dir].compactMap { $0 } + ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin",
                       "/usr/bin", "/bin", "/usr/sbin", "/sbin", env["PATH"] ?? ""]).joined(separator: ":")
        return env
    }

    /// Terminal output without its colors and cursor moves.
    nonisolated static func plain(_ data: Data) -> String {
        let raw = String(decoding: data, as: UTF8.self)
        let noEscapes = raw.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]|\u{1B}\\][^\u{07}\u{1B}]*(\u{07}|\u{1B}\\\\)|\u{1B}[()][0-9A-Za-z]|\u{1B}[=>]",
                                                 with: "", options: .regularExpression)
        return noEscapes.replacingOccurrences(of: "\r", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    fileprivate func log(_ message: String) {
        appendAppLog("nb.log", "[Ask] \(message)")
    }
}
#endif
