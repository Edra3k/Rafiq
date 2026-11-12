#if !APPSTORE
import Foundation

// MARK: - Claude's limits, asked to Claude Code itself
//
// The statusline relay only runs in the terminal; sessions from the Claude app never send
// their limits. So Rafiq asks Claude Code the same thing /usage shows, through its structured
// control protocol: no prompt, no model call, no tool, no hook, no MCP server. Claude Code signs
// in by itself. At most every five minutes, and only when the gauge is on screen.

enum ClaudeAccountUsage {
    static func executable() -> String? {
        let home = NSHomeDirectory()
        let candidates = ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude", "/opt/homebrew/bin/claude",
                          "/usr/local/bin/claude", "\(home)/.npm-global/bin/claude", "\(home)/.bun/bin/claude"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func fetch() async -> PlanUsage? {
        guard let claude = executable() else { return nil }
        return await Task.detached { read(claude: claude) }.value
    }

    private static func read(claude: String) -> PlanUsage? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: claude)
        process.arguments = ["--print", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                             "--no-session-persistence", "--tools", "", "--strict-mcp-config", "--mcp-config", "{\"mcpServers\":{}}",
                             "--setting-sources", "", "--settings", "{\"disableAllHooks\":true}"]
        var env = ProcessInfo.processInfo.environment
        env["CLAUDE_CODE_ENTRYPOINT"] = nil
        env["CLAUDECODE"] = nil
        env["PATH"] = [URL(fileURLWithPath: claude).deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin",
                       "/usr/bin", "/bin", env["PATH"] ?? ""].joined(separator: ":")
        process.environment = env
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        defer { if process.isRunning { process.terminate() } }

        func send(_ id: String, _ request: [String: Any]) {
            let line = ["type": "control_request", "request_id": id, "request": request] as [String: Any]
            guard var data = try? JSONSerialization.data(withJSONObject: line) else { return }
            data.append(0x0A)
            try? input.fileHandleForWriting.write(contentsOf: data)
        }
        send("init", ["subtype": "initialize"])
        send("usage", ["subtype": "get_usage"])

        // Read lines until the usage answer; a watchdog ends Claude Code after 25 s.
        let watchdog = ProcessBox(process)
        DispatchQueue.global().asyncAfter(deadline: .now() + 25) { watchdog.stop() }
        var buffer = Data()
        let handle = output.fileHandleForReading
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { return nil }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      json["type"] as? String == "control_response",
                      let response = json["response"] as? [String: Any],
                      response["request_id"] as? String == "usage" else { continue }
                return (response["response"] as? [String: Any]).flatMap(parse)
            }
        }
    }

    private final class ProcessBox: @unchecked Sendable {
        let process: Process
        init(_ process: Process) { self.process = process }
        func stop() { if process.isRunning { process.terminate() } }
    }

    static func parse(_ response: [String: Any]) -> PlanUsage? {
        guard response["rate_limits_available"] as? Bool == true,
              let limits = response["rate_limits"] as? [String: Any] else { return nil }
        func window(_ key: String) -> PlanWindow? {
            guard let w = limits[key] as? [String: Any],
                  let pct = (w["utilization"] as? NSNumber)?.doubleValue,
                  let reset = (w["resets_at"] as? String).flatMap(date) else { return nil }
            return PlanWindow(usedPct: min(100, max(0, pct)), resetsAt: reset)
        }
        let usage = PlanUsage(fiveHour: window("five_hour"), sevenDay: window("seven_day"), updatedAt: Date())
        return usage.fiveHour == nil && usage.sevenDay == nil ? nil : usage
    }

    static func date(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: text) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }
}

// MARK: - Tokens, from Claude Code's own transcripts

/// Prices per million tokens, from Anthropic's public pricing (API value of the plan's use).
enum ClaudePrices {
    struct Price { let input, output, cacheRead, cacheWrite5m, cacheWrite1h: Double }

    static func price(for model: String) -> Price? {
        let m = model.lowercased()
        let table: [(String, Price)] = [
            ("claude-fable", Price(input: 10, output: 50, cacheRead: 0.25, cacheWrite5m: 12.5, cacheWrite1h: 20)),
            ("claude-mythos", Price(input: 10, output: 50, cacheRead: 0.25, cacheWrite5m: 12.5, cacheWrite1h: 20)),
            ("claude-opus-5-5", Price(input: 4, output: 20, cacheRead: 0.2, cacheWrite5m: 5, cacheWrite1h: 8)),
            ("claude-opus-5", Price(input: 5, output: 25, cacheRead: 0.5, cacheWrite5m: 6.25, cacheWrite1h: 10)),
            ("claude-opus-4-1", Price(input: 15, output: 75, cacheRead: 1.5, cacheWrite5m: 18.75, cacheWrite1h: 30)),
            ("claude-opus-4-", Price(input: 5, output: 25, cacheRead: 0.5, cacheWrite5m: 6.25, cacheWrite1h: 10)),
            ("claude-opus-4", Price(input: 15, output: 75, cacheRead: 1.5, cacheWrite5m: 18.75, cacheWrite1h: 30)),
            ("claude-sonnet-5-5", Price(input: 2, output: 10, cacheRead: 0.1, cacheWrite5m: 2.5, cacheWrite1h: 4)),
            ("claude-sonnet-5", Price(input: 2, output: 10, cacheRead: 0.2, cacheWrite5m: 2.5, cacheWrite1h: 4)),
            ("claude-sonnet", Price(input: 3, output: 15, cacheRead: 0.3, cacheWrite5m: 3.75, cacheWrite1h: 6)),
            ("claude-haiku-5", Price(input: 0.1, output: 0.5, cacheRead: 0.01, cacheWrite5m: 0.125, cacheWrite1h: 0.2)),
            ("claude-haiku-4", Price(input: 1, output: 5, cacheRead: 0.1, cacheWrite5m: 1.25, cacheWrite1h: 2)),
            ("claude-3-5-haiku", Price(input: 0.8, output: 4, cacheRead: 0.08, cacheWrite5m: 1, cacheWrite1h: 1.6)),
        ]
        return table.first { m.hasPrefix($0.0) }?.1
    }

    /// "claude-opus-5-5-20261001" → "Opus 5.5".
    static func pretty(_ model: String) -> String {
        let parts = model.replacingOccurrences(of: "claude-", with: "").split(separator: "-")
        guard let family = parts.first else { return model }
        let version = parts.dropFirst().prefix { $0.count <= 2 && Int($0) != nil }.joined(separator: ".")
        return family.prefix(1).uppercased() + family.dropFirst() + (version.isEmpty ? "" : " " + version)
    }
}

struct TokenEntry: Sendable {
    let day: Date
    let project: String
    let model: String
    let tokens: Int
    let cacheRead: Int
    let cost: Double
}

@MainActor
final class TokenLedger: ObservableObject {
    static let shared = TokenLedger()

    struct Totals { var tokens = 0, cacheRead = 0; var cost = 0.0 }

    @Published private(set) var today = Totals()
    @Published private(set) var week = Totals()
    /// The last 7 days, oldest first.
    @Published private(set) var days: [(day: Date, cost: Double)] = []
    @Published private(set) var projects: [(name: String, share: Double)] = []
    @Published private(set) var models: [(name: String, share: Double)] = []
    @Published private(set) var loading = false
    @Published private(set) var lastRead: Date?

    private var cache: [String: (stamp: String, entries: [TokenEntry])] = [:]

    func refresh(force: Bool = false) {
        guard !loading else { return }
        if !force, let last = lastRead, Date().timeIntervalSince(last) < 60 { return }
        loading = true
        let known = cache
        Task {
            let (entries, newCache) = await Task.detached { Self.scan(cache: known) }.value
            cache = newCache
            apply(entries)
            loading = false
            lastRead = Date()
        }
    }

    private func apply(_ entries: [TokenEntry]) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let weekStart = cal.date(byAdding: .day, value: -6, to: start) ?? start
        var t = Totals(), w = Totals()
        var perDay: [Date: Double] = [:], perProject: [String: Double] = [:], perModel: [String: Double] = [:]
        for e in entries where e.day >= weekStart {
            w.tokens += e.tokens; w.cacheRead += e.cacheRead; w.cost += e.cost
            if e.day >= start { t.tokens += e.tokens; t.cacheRead += e.cacheRead; t.cost += e.cost }
            perDay[cal.startOfDay(for: e.day), default: 0] += e.cost
            perProject[e.project, default: 0] += e.cost
            perModel[ClaudePrices.pretty(e.model), default: 0] += e.cost
        }
        today = t
        week = w
        days = (0..<7).map { offset in
            let d = cal.date(byAdding: .day, value: offset - 6, to: start) ?? start
            return (d, perDay[d] ?? 0)
        }
        let total = max(w.cost, 0.0001)
        projects = perProject.sorted { $0.value > $1.value }.prefix(4).map { ($0.key, $0.value / total) }
        models = perModel.sorted { $0.value > $1.value }.prefix(3).map { ($0.key, $0.value / total) }
    }

    nonisolated private static func scan(cache: [String: (stamp: String, entries: [TokenEntry])])
        -> ([TokenEntry], [String: (stamp: String, entries: [TokenEntry])]) {
        let root = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")
        let since = Date().addingTimeInterval(-8 * 86400)
        var result: [TokenEntry] = []
        var newCache: [String: (stamp: String, entries: [TokenEntry])] = [:]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else {
            return ([], [:])
        }
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            guard let modified = values?.contentModificationDate, modified >= since else { continue }
            let stamp = "\(modified.timeIntervalSince1970)-\(values?.fileSize ?? 0)"
            if let hit = cache[url.path], hit.stamp == stamp {
                newCache[url.path] = hit
                result += hit.entries
                continue
            }
            let entries = read(url, since: since)
            newCache[url.path] = (stamp, entries)
            result += entries
        }
        return (result, newCache)
    }

    nonisolated private static func read(_ url: URL, since: Date) -> [TokenEntry] {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return [] }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        // A streamed message repeats its id with growing usage: the last one counts.
        var byId: [String: TokenEntry] = [:]
        var order: [String] = []
        var sessionProject: String?
        let marker = Data("\"usage\"".utf8)
        var start = data.startIndex
        while start < data.endIndex {
            let end = data[start...].firstIndex(of: 0x0A) ?? data.endIndex
            let line = data[start..<end]
            start = end < data.endIndex ? data.index(after: end) : end
            guard line.range(of: marker) != nil,
                  let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let message = json["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any],
                  let model = message["model"] as? String, model.hasPrefix("claude"),
                  let stampText = json["timestamp"] as? String, let when = iso.date(from: stampText), when >= since else { continue }
            func n(_ key: String) -> Int { (usage[key] as? NSNumber)?.intValue ?? 0 }
            let input = n("input_tokens"), output = n("output_tokens"), read = n("cache_read_input_tokens")
            let creation = usage["cache_creation"] as? [String: Any]
            let write1h = (creation?["ephemeral_1h_input_tokens"] as? NSNumber)?.intValue ?? 0
            let write5m = (creation?["ephemeral_5m_input_tokens"] as? NSNumber)?.intValue ?? max(0, n("cache_creation_input_tokens") - write1h)
            var cost = 0.0
            if let p = ClaudePrices.price(for: model) {
                cost = (Double(input) * p.input + Double(output) * p.output + Double(read) * p.cacheRead
                        + Double(write5m) * p.cacheWrite5m + Double(write1h) * p.cacheWrite1h) / 1_000_000
            }
            // The folder the session started in names the project (a later `cd` doesn't).
            if sessionProject == nil, let cwd = json["cwd"] as? String, !cwd.isEmpty {
                sessionProject = (cwd as NSString).lastPathComponent
            }
            let project = sessionProject ?? url.deletingLastPathComponent().lastPathComponent
            let entry = TokenEntry(day: when, project: project, model: model,
                                   tokens: input + output + write5m + write1h, cacheRead: read, cost: cost)
            let id = (message["id"] as? String) ?? UUID().uuidString
            if byId[id] == nil { order.append(id) }
            byId[id] = entry
        }
        return order.compactMap { byId[$0] }
    }

    static func compact(_ n: Int) -> String {
        let d = Double(n)
        if d >= 1_000_000_000 { return String(format: "%.1f G", d / 1_000_000_000) }
        if d >= 1_000_000 { return String(format: "%.1f M", d / 1_000_000) }
        if d >= 1_000 { return String(format: "%.0f k", d / 1_000) }
        return "\(n)"
    }

    /// "01:23" for a running recording.
    static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// "2 h 5 min", "6 d 3 h".
    static func span(_ seconds: TimeInterval) -> String {
        let f = DateComponentsFormatter()
        f.unitsStyle = .abbreviated
        f.maximumUnitCount = 2
        f.allowedUnits = seconds >= 86400 ? [.day, .hour] : [.hour, .minute]
        return f.string(from: max(60, seconds)) ?? ""
    }

    static func dollars(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = value < 100 ? 2 : 0
        return f.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }
}
#endif
