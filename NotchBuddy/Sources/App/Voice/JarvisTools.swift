#if !APPSTORE
import AppKit
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Jarvis: what Rafiq's on-device brain (Apple Intelligence) can do
//
// The tools VoiceBrain gives Apple's on-device model beyond pills, music and services: hand a
// task to Hermes or Claude (or carry on the last Claude Code conversation), say where the agents
// are, the prayers, a Pomodoro, the day (what finished, what to push, the server), and bring up
// a request that waits. Nothing here answers a request: the card opens, the click is the user's.
// The same answers serve Siri and Shortcuts (RafiqIntents.swift).

@MainActor
enum JarvisFacts {
    /// Where the agents are: what runs (and its step), what waits for an OK, what just ended.
    static func agents() -> String {
        let state = AppState.shared
        var parts: [String] = []
        for (_, turns) in TurnHistory.shared.turns {
            guard let turn = turns.last else { continue }
            let name = turn.title.isEmpty ? URL(fileURLWithPath: turn.cwd).lastPathComponent : turn.title
            if turn.endedAt == nil {
                let step = turn.steps.last?.label ?? "thinking"
                parts.append("\(name): working for \(SessionFullView.duration(Date().timeIntervalSince(turn.startedAt))), now \(step)")
            } else if let end = turn.endedAt, Date().timeIntervalSince(end) < 6 * 3600 {
                let answer = turn.answer.replacingOccurrences(of: "\n", with: " ").prefix(160)
                parts.append("\(name): finished \(SessionFullView.duration(Date().timeIntervalSince(end))) ago. It said: \(answer)")
            }
        }
        for job in AskRunner.shared.jobs.prefix(3) {
            let who = job.target == .hermes ? "Hermes" : "Claude"
            switch job.state {
            case .running: parts.append("\(who) task \"\(job.text.prefix(60))\": running, \(job.steps.last ?? "starting")")
            case .done: parts.append("\(who) task \"\(job.text.prefix(60))\": done. \(job.answer.prefix(160))")
            default: break
            }
        }
        if let a = state.pendingApproval {
            parts.append("A request waits for the user's OK (\(a.queueCount) in all): \(a.tool) \(a.command.prefix(80))")
        }
        return parts.isEmpty ? "No agent is working and nothing waits." : parts.joined(separator: "\n")
    }

    /// The day's prayers: the next one, and today's times only when asked (`all`).
    static func prayers(all: Bool = false) -> String {
        let prayer = PrayerController.shared
        guard AppState.shared.activeIntegrations.contains(PrayerController.pillId), let today = prayer.today else {
            return "The Prayer pill is off: no prayer times."
        }
        var parts: [String] = []
        if let next = prayer.next(at: Date()) {
            parts.append("The next prayer is \(PrayerController.name(next.prayer)), at \(prayer.clock(next.at)), in \(PrayerController.countdown(next.at.timeIntervalSinceNow))")
        }
        guard all else { return parts.joined() + "." }
        let times = Prayer.allCases.filter(\.isObligatory).compactMap { p in
            today.time(p).map { "\(PrayerController.name(p)) \(prayer.clock($0))\(prayer.prayed.contains(p) ? " (prayed)" : "")" }
        }
        parts.append("Today: " + times.joined(separator: ", "))
        return parts.joined(separator: ". ")
    }

    /// The day so far: turns, projects to push, the server.
    static func day() -> String {
        let cal = Calendar.current
        let now = Date()
        let start = cal.date(bySettingHour: 20, minute: 0, second: 0, of: cal.date(byAdding: .day, value: -1, to: now) ?? now) ?? now
        let turns = TurnLog.shared.turns(from: start)
        var parts = ["\(turns.count) agent turns since last evening" + (turns.isEmpty ? "" : ": " + turns.suffix(4).map { "\($0.project) (\($0.prompt.prefix(50)))" }.joined(separator: "; "))]
        let toPush = SessionLauncher.shared.projects.compactMap { p -> String? in
            guard let g = GitStatusStore.shared.summary(for: p), g.ahead > 0 || g.changed > 0 else { return nil }
            return "\(SessionLauncher.name(of: p)): \(g.ahead) commits to push, \(g.changed) files changed"
        }
        parts.append(toPush.isEmpty ? "Nothing to push." : toPush.joined(separator: "; "))
        let lab = Homelab.shared
        if let fullest = lab.storages.max(by: { $0.share < $1.share }), lab.lastUpdate != nil {
            parts.append("Server: \(lab.nodes.allSatisfy(\.online) ? "up" : "a node is offline"), fullest disk \(Int(fullest.share * 100)) %, \(lab.guests.count) VMs and containers")
        }
        return parts.joined(separator: ". ")
    }

    /// Brings up the waiting request's card (never answers it).
    static func showRequest() -> String {
        guard let a = AppState.shared.pendingApproval else { return "No request waits." }
        AppState.shared.focusId = a.pillId
        NotificationCenter.default.post(name: .hookExpand, object: IslandView.approval)
        return "The card is open: \(a.tool) \(a.command.prefix(80)). The user decides with a click."
    }

    static func pomodoro(_ action: String) -> String {
        let c = CoucoudoroController.shared
        switch action {
        case "start":
            if c.phase == .idle { c.begin(force: true) }
            guard c.phase != .idle else { return "The Pomodoro could not start." }
            let left = c.remaining(at: Date()).map { PrayerController.countdown($0) } ?? ""
            return "Pomodoro started: work for \(left)."
        case "stop":
            c.end()
            return "Pomodoro stopped."
        default:
            if c.phase == .idle { return "No Pomodoro running." }
            let left = c.remaining(at: Date()).map { PrayerController.countdown($0) } ?? "?"
            return "Pomodoro \(c.phase == .work ? "work" : "break"), \(left) left."
        }
    }
}

#if canImport(FoundationModels)

@available(macOS 26, *)
struct AgentTaskTool: Tool, @unchecked Sendable {
    let name = "agent_task"
    let description = "Give a task to an agent that works in the background: hermes (the server, the home, local models), claude (code; with no project named it carries on the last Claude Code conversation), or auto. Use it for anything to do, check, fix or build."

    @Generable
    struct Arguments {
        @Guide(description: "hermes | claude | auto")
        var agent: String
        @Guide(description: "The task in the user's words")
        var task: String
    }

    let collector: IntentCollector

    func call(arguments: Arguments) async throws -> String {
        let target: AskTarget = ["hermes": .hermes, "claude": .claude][arguments.agent.lowercased()] ?? .auto
        collector.append(.askAgent(target: target, text: arguments.task))
        return "task handed to \(arguments.agent)"
    }
}

@available(macOS 26, *)
struct AgentsNowTool: Tool, @unchecked Sendable {
    let name = "agents_now"
    let description = "Where the coding agents and Hermes are right now: what runs and its current step, what finished and what it said, what waits for the user's OK."

    @Generable
    struct Arguments {
        @Guide(description: "Always \"all\"")
        var scope: String
    }

    func call(arguments: Arguments) async throws -> String { await JarvisFacts.agents() }
}

@available(macOS 26, *)
struct PrayerTool: Tool, @unchecked Sendable {
    let name = "prayer"
    let description = "The next prayer and how long until it; with \"today\", all of today's prayer times."

    @Generable
    struct Arguments {
        @Guide(description: "next (the next prayer) | today (all of today's times)")
        var query: String
    }

    func call(arguments: Arguments) async throws -> String {
        await JarvisFacts.prayers(all: arguments.query.lowercased() == "today")
    }
}

@available(macOS 26, *)
struct DayTool: Tool, @unchecked Sendable {
    let name = "day"
    let description = "The day so far: agent turns since last evening, projects with commits to push, the home server's state."

    @Generable
    struct Arguments {
        @Guide(description: "Always \"summary\"")
        var query: String
    }

    func call(arguments: Arguments) async throws -> String { await JarvisFacts.day() }
}

@available(macOS 26, *)
struct PomodoroTool: Tool, @unchecked Sendable {
    let name = "pomodoro"
    let description = "Start, stop or check the Pomodoro focus timer."

    @Generable
    struct Arguments {
        @Guide(description: "start | stop | status")
        var action: String
    }

    func call(arguments: Arguments) async throws -> String { await JarvisFacts.pomodoro(arguments.action) }
}

@available(macOS 26, *)
struct RequestTool: Tool, @unchecked Sendable {
    let name = "show_request"
    let description = "Open the card of the request an agent waits on, so the user can read it and decide. It never allows or denies anything."

    @Generable
    struct Arguments {
        @Guide(description: "Always \"open\"")
        var action: String
    }

    func call(arguments: Arguments) async throws -> String { await JarvisFacts.showRequest() }
}

#endif // canImport(FoundationModels)
#endif // !APPSTORE
