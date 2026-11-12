import AppKit
import SwiftUI

/// "Details": the open island grows to show a whole turn of the focused session — what you
/// asked and what the agent answered, every step (opened, the whole command), the files
/// changed (opened, their diff), the guard's tally, the Git state and the shortcuts; ‹ › go
/// back through the last turns. Under it, a field to answer the agent: Claude Code carries on
/// the same conversation in the background (SessionReply), its approvals still on their card.
struct SessionFullView: View {
    @ObservedObject var state: AppState
    let openTarget: () -> Void
    @ObservedObject private var history = TurnHistory.shared
    @ObservedObject private var riskLog = CommandRiskLog.shared
    @ObservedObject private var git = GitStatusStore.shared
    #if !APPSTORE
    @ObservedObject private var reply = SessionReply.shared
    #endif

    /// Which turn is shown, counted from the latest (0).
    @State private var back = 0
    @State private var openStep: UUID?
    @State private var replyText = ""
    @State private var replyNote: String?
    @State private var copied = false
    @FocusState private var replyFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            CardBackground(wash: nil)
            if let task = state.focusTask {
                let turns = history.turns(for: task)
                let index = turns.isEmpty ? nil : max(0, turns.count - 1 - min(back, turns.count - 1))
                turnNavigator(count: turns.count, index: index)
                content(task, turn: index.map { turns[$0] })
                    .padding(.leading, 108)
                    .padding(.trailing, 16)
                    .padding(.vertical, 12)
            }
        }
        .onChange(of: state.focusId) { _, _ in back = 0; openStep = nil }
    }

    // MARK: Left column: the turns

    @ViewBuilder
    private func turnNavigator(count: Int, index: Int?) -> some View {
        if count > 1, let index {
            VStack(spacing: 2) {
                Text(verbatim: String(format: String(localized: "details.turn %lld %lld", defaultValue: "Turn %lld of %lld"),
                                      Int64(index + 1), Int64(count)))
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#6B7079"))
                HStack(spacing: 10) {
                    turnArrow("chevron.left", enabled: index > 0) { back += 1; openStep = nil }
                    turnArrow("chevron.right", enabled: index < count - 1) { back -= 1; openStep = nil }
                }
            }
            .frame(width: 96)
            .padding(.top, 150)
        }
    }

    private func turnArrow(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(hex: enabled ? "#C0C4CC" : "#3A3D42"))
                .frame(width: 22, height: 18)
                .background(Capsule().fill(Color.white.opacity(enabled ? 0.08 : 0.03)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: The turn

    private func content(_ task: AgentTask, turn: TurnHistory.Turn?) -> some View {
        let agent = agentName(task)
        let files = turn.map { history.files(of: $0) } ?? []
        let rows = turn.map { Self.rows($0.steps) } ?? []
        let summary = git.summary(for: task.sessionCwd)
        return VStack(alignment: .leading, spacing: 7) {
            header(task, turn: turn)
            if let turn { exchange(turn, agent: agent) }
            HStack(alignment: .top, spacing: 14) {
                stepsColumn(rows, turn: turn)
                    .frame(maxWidth: .infinity, alignment: .leading)
                sideColumn(files: files, steps: turn?.steps ?? [], git: summary)
                    .frame(width: 190, alignment: .topLeading)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            shortcuts(task, turn: turn, files: files)
            #if !APPSTORE
            if let turn, SessionReply.canReply(pill: task.pill) {
                replyBar(turn, agent: agent)
            }
            #endif
        }
        .onAppear { git.refresh(task.sessionCwd) }
    }

    private func header(_ task: AgentTask, turn: TurnHistory.Turn?) -> some View {
        HStack(spacing: 6) {
            Circle().fill(Color(hex: task.color)).frame(width: 8, height: 8)
            Text(verbatim: turn?.title.isEmpty == false ? turn!.title : task.name)
                .font(.system(size: 13, weight: .semibold)).lineLimit(1)
            TimelineView(.periodic(from: .now, by: 1)) { tl in
                Text(verbatim: placeLine(task, turn: turn, now: tl.date))
                    .font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            if let turn { stateChip(turn) }
            Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { state.view = .overview } }) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundColor(Color(hex: "#6B7079"))
                    .frame(width: 18, height: 18).background(Color.white.opacity(0.06)).clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    /// "· ~/Rafiq · Opus 5.5 · 4 min 12 s"
    private func placeLine(_ task: AgentTask, turn: TurnHistory.Turn?, now: Date) -> String {
        var parts: [String] = []
        if let cwd = turn?.cwd ?? task.sessionCwd, !cwd.isEmpty {
            parts.append((cwd as NSString).abbreviatingWithTildeInPath)
        }
        if let model = turn?.model { parts.append(model) }
        if let turn {
            parts.append(Self.duration((turn.endedAt ?? now).timeIntervalSince(turn.startedAt)))
        }
        return parts.isEmpty ? "" : "· " + parts.joined(separator: " · ")
    }

    private func stateChip(_ turn: TurnHistory.Turn) -> some View {
        let running = turn.endedAt == nil
        return Text(verbatim: running
                    ? String(localized: "details.running", defaultValue: "Working")
                    : String(localized: "details.done", defaultValue: "Done"))
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(Color(hex: running ? "#F5A524" : "#34D399"))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(Color(hex: "#1D1F23")))
    }

    /// What you asked, and what the agent answered (or that it is on it).
    private func exchange(_ turn: TurnHistory.Turn, agent: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            label(String(localized: "details.you-asked", defaultValue: "You asked"))
            Text(verbatim: turn.prompt.isEmpty ? "—" : turn.prompt)
                .font(.system(size: 11.5)).foregroundColor(Color(hex: "#E6E8EC"))
                .lineLimit(2).truncationMode(.tail)
                .textSelection(.enabled)
            label(turn.endedAt == nil
                  ? String(format: String(localized: "details.working %@", defaultValue: "%@ is working…"), agent)
                  : String(format: String(localized: "details.answered %@", defaultValue: "%@ answered"), agent))
                .padding(.top, 3)
            if !turn.answer.isEmpty {
                // Short: as it is. Long: three lines' worth, scrolled.
                ViewThatFits(in: .vertical) {
                    answerText(turn.answer).fixedSize(horizontal: false, vertical: true)
                    ScrollView { answerText(turn.answer) }.frame(height: 54)
                }
                .frame(maxHeight: 54, alignment: .topLeading)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "#0E0F11")))
    }

    private func answerText(_ answer: String) -> some View {
        Text(verbatim: answer)
            .font(.system(size: 11.5)).foregroundColor(Color(hex: "#C0C4CC"))
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    // MARK: Steps

    /// A row of the steps list: one step, or reads that follow each other folded into one.
    struct Row: Identifiable {
        let id: UUID
        var tool: String
        var label: String
        var detail: String
        var level: CommandRisk.Level
        var reason: CommandRisk.Reason
        var start: Date
        var end: Date?
    }

    static func rows(_ steps: [TurnHistory.Step]) -> [Row] {
        var rows: [Row] = []
        var i = 0
        while i < steps.count {
            let s = steps[i]
            if TurnHistory.isRead(s.tool) {
                var j = i
                while j + 1 < steps.count && TurnHistory.isRead(steps[j + 1].tool) { j += 1 }
                if j > i {
                    let group = steps[i...j]
                    let worst = group.max { $0.risk.level < $1.risk.level }!
                    rows.append(Row(id: s.id, tool: "Read",
                                    label: String(format: String(localized: "details.reads %lld", defaultValue: "%lld files read"), Int64(group.count)),
                                    detail: group.map(\.detail).joined(separator: "\n"),
                                    level: worst.risk.level, reason: worst.risk.reason,
                                    start: s.at, end: j + 1 < steps.count ? steps[j + 1].at : nil))
                    i = j + 1
                    continue
                }
            }
            rows.append(Row(id: s.id, tool: s.tool, label: s.label, detail: s.detail, level: s.risk.level, reason: s.risk.reason,
                            start: s.at, end: i + 1 < steps.count ? steps[i + 1].at : nil))
            i += 1
        }
        return rows
    }

    private func stepsColumn(_ rows: [Row], turn: TurnHistory.Turn?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            label(String(format: String(localized: "session.steps %lld", defaultValue: "Steps of the turn · %lld"),
                         Int64(turn?.steps.count ?? 0)))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { row in stepRow(row, turnEnd: turn?.endedAt, cwd: turn?.cwd ?? "").id(row.id) }
                        if rows.isEmpty {
                            Text(String(localized: "session.no-steps", defaultValue: "No step rated yet in this turn."))
                                .font(.system(size: 11)).foregroundColor(Color(hex: "#6B7079"))
                        }
                    }
                }
                .onAppear { if let last = rows.last { proxy.scrollTo(last.id, anchor: .bottom) } }
                .onChange(of: rows.count) { _, _ in
                    if openStep == nil, let last = rows.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func stepRow(_ row: Row, turnEnd: Date?, cwd: String) -> some View {
        let open = openStep == row.id
        return VStack(alignment: .leading, spacing: 3) {
            Button(action: { withAnimation(.easeOut(duration: 0.15)) { openStep = open ? nil : row.id } }) {
                HStack(spacing: 7) {
                    Circle().fill(RiskBadge.color(row.level)).frame(width: 6, height: 6)
                    Image(systemName: TurnHistory.symbol(row.tool))
                        .font(.system(size: 9, weight: .semibold)).foregroundColor(Color(hex: "#6B7079"))
                        .frame(width: 12)
                    Text(verbatim: row.label).font(.system(size: 11)).foregroundColor(Color(hex: "#C0C4CC"))
                        .lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 4)
                    if row.level != .safe {
                        Text(verbatim: row.reason.label).font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(RiskBadge.color(row.level)).lineLimit(1).fixedSize()
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { tl in
                        Text(verbatim: Self.duration((row.end ?? turnEnd ?? tl.date).timeIntervalSince(row.start)))
                            .font(.system(size: 9.5)).monospacedDigit().foregroundColor(Color(hex: "#6B7079"))
                    }
                    .fixedSize()
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                Text(verbatim: cwd.isEmpty ? row.detail : row.detail.replacingOccurrences(of: cwd + "/", with: ""))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(Color(hex: "#C0C4CC"))
                    .textSelection(.enabled)
                    .lineLimit(12)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: "#111316")))
                    .padding(.leading, 18).padding(.bottom, 4)
            }
        }
        .overlay(Rectangle().fill(Color.white.opacity(0.05)).frame(height: 0.5), alignment: .top)
    }

    // MARK: Files, guard, Git

    private func sideColumn(files: [TurnHistory.FileChange], steps: [TurnHistory.Step], git summary: GitSummary?) -> some View {
        let tally = Dictionary(grouping: steps, by: { $0.risk.level }).mapValues(\.count)
        let short = Self.shortPaths(files.map(\.path))
        return VStack(alignment: .leading, spacing: 4) {
            label(files.isEmpty
                  ? String(localized: "session.files-changed", defaultValue: "Files changed")
                  : String(format: String(localized: "details.files %lld", defaultValue: "Files · %lld"), Int64(files.count)))
            if files.isEmpty {
                Text(verbatim: "—").font(.system(size: 11)).foregroundColor(Color(hex: "#6B7079"))
            }
            ForEach(files.prefix(5)) { f in
                Button(action: { showDiff(f.diffId) }) {
                    HStack(spacing: 5) {
                        Text(verbatim: short[f.path] ?? (f.path as NSString).lastPathComponent)
                            .font(.system(size: 10.5, design: .monospaced)).foregroundColor(Color(hex: "#C0C4CC"))
                            .lineLimit(1).truncationMode(.head)
                        Spacer(minLength: 2)
                        if f.added > 0 { Text(verbatim: "+\(f.added)").foregroundColor(Color(hex: "#34D399")) }
                        if f.removed > 0 { Text(verbatim: "−\(f.removed)").foregroundColor(Color(hex: "#F4505E")) }
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(f.path)
            }
            if files.count > 5 {
                Text(verbatim: String(format: String(localized: "details.more %lld", defaultValue: "+ %lld more"), Int64(files.count - 5)))
                    .font(.system(size: 10)).foregroundColor(Color(hex: "#6B7079"))
            }

            label(String(localized: "watch.guard", defaultValue: "Guard")).padding(.top, 6)
            guardBar(tally)
            Text(verbatim: [CommandRisk.Level.safe, .caution, .high]
                    .filter { (tally[$0] ?? 0) > 0 }
                    .map { "\(tally[$0] ?? 0) \(SessionFullView.levelName($0))" }
                    .joined(separator: " · ").ifEmpty("—"))
                .font(.system(size: 10)).foregroundColor(Color(hex: "#9CA1AA")).lineLimit(2)

            if let g = summary {
                label("Git").padding(.top, 6)
                HStack(spacing: 5) {
                    tag("⎇ \(g.branch)", "#C0C4CC")
                    if g.ahead > 0 { tag(String(format: String(localized: "session.unpushed %lld", defaultValue: "↑ %lld not pushed"), Int64(g.ahead)), "#F5A524") }
                    if g.changed > 0 { tag("● \(g.changed)", "#C0C4CC") }
                }
            }
        }
    }

    private func guardBar(_ tally: [CommandRisk.Level: Int]) -> some View {
        let levels: [CommandRisk.Level] = [.safe, .caution, .high]
        let total = max(1, levels.reduce(0) { $0 + (tally[$1] ?? 0) })
        return GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(levels, id: \.self) { level in
                    let n = tally[level] ?? 0
                    if n > 0 {
                        Rectangle().fill(RiskBadge.color(level))
                            .frame(width: max(3, geo.size.width * CGFloat(n) / CGFloat(total)))
                    }
                }
                if tally.values.reduce(0, +) == 0 {
                    Rectangle().fill(Color.white.opacity(0.08))
                }
            }
        }
        .frame(height: 5)
        .clipShape(Capsule())
    }

    // MARK: Shortcuts

    private func shortcuts(_ task: AgentTask, turn: TurnHistory.Turn?, files: [TurnHistory.FileChange]) -> some View {
        HStack(spacing: 5) {
            shortcut("terminal", String(localized: "session.open-terminal", defaultValue: "Terminal"), action: openTarget)
            if let last = files.last {
                shortcut("plusminus", String(localized: "session.last-diff", defaultValue: "Last diff")) { showDiff(last.diffId) }
            }
            if let cwd = turn?.cwd ?? task.sessionCwd, !cwd.isEmpty {
                shortcut("folder", String(localized: "session.folder", defaultValue: "Folder")) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: cwd))
                }
            }
            if let answer = turn?.answer, !answer.isEmpty {
                shortcut(copied ? "checkmark" : "doc.on.doc", String(localized: "ask.copy", defaultValue: "Copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(answer, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }
                #if !APPSTORE
                shortcut("speaker.wave.2", String(localized: "ask.read", defaultValue: "Read aloud")) {
                    AskRunner.shared.readAloud(text: answer)
                }
                #endif
            }
        }
    }

    private func showDiff(_ id: Int) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { state.view = .overview }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            NotificationCenter.default.post(name: .islandShowDiff, object: id)
        }
    }

    // MARK: Reply

    #if !APPSTORE
    private func replyBar(_ turn: TurnHistory.Turn, agent: String) -> some View {
        let busy = turn.endedAt == nil || reply.running.contains(turn.sessionId)
        let empty = replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                TextField(String(format: String(localized: "details.reply.placeholder %@", defaultValue: "Reply to %@…"), agent),
                          text: $replyText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .lineLimit(1...3)
                    .focused($replyFocused)
                    .onSubmit { send(turn) }
                    .disabled(busy)
                Button(action: { send(turn) }) {
                    Image(systemName: busy ? "ellipsis" : "arrow.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(busy || empty ? Color(hex: "#4A4D52") : Color.white))
                }
                .buttonStyle(.plain)
                .disabled(busy || empty)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
            Text(verbatim: failureText(turn.sessionId) ?? replyNote ?? (busy
                ? String(localized: "details.reply.busy", defaultValue: "You can answer once the turn ends.")
                : String(localized: "details.reply.hint", defaultValue: "Carries on this conversation in the background. A risky command still waits for your click.")))
                .font(.system(size: 9.5)).foregroundColor(Color(hex: "#6B7079")).lineLimit(1)
        }
    }

    private func failureText(_ session: String) -> String? {
        switch reply.failures[session] {
        case .notSignedIn?:
            return String(localized: "details.reply.sign-in", defaultValue: "Sign in to claude first: run claude in a terminal, then /login.")
        case .ended(let tail)?:
            return String(format: String(localized: "details.reply.failed %@", defaultValue: "Claude stopped: %@"), tail)
        case nil:
            return nil
        }
    }

    private func send(_ turn: TurnHistory.Turn) {
        guard turn.endedAt != nil else { return }
        switch reply.send(replyText, sessionId: turn.sessionId, cwd: turn.cwd, pillId: turn.pill) {
        case .started:
            replyText = ""
            replyFocused = false
            back = 0
            replyNote = String(localized: "details.reply.sent", defaultValue: "Sent. The new turn shows here.")
        case .empty:
            break
        case .busy:
            replyNote = String(localized: "details.reply.busy", defaultValue: "You can answer once the turn ends.")
        case .noClaude:
            replyNote = String(localized: "details.reply.no-claude", defaultValue: "The claude command wasn't found on this Mac.")
        case .noFolder:
            replyNote = String(localized: "details.reply.no-folder", defaultValue: "The session's folder is gone.")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { replyNote = nil }
    }
    #endif

    // MARK: Helpers

    private func agentName(_ task: AgentTask) -> String {
        switch PillCatalog.basePillId(task.pill) {
        case "integration_claude", "agent_cursor", "agent_claude-desktop": return "Claude"
        default: return task.name
        }
    }

    static func levelName(_ level: CommandRisk.Level) -> String {
        switch level {
        case .safe: return String(localized: "session.level.safe", defaultValue: "read only")
        case .caution: return String(localized: "session.level.caution", defaultValue: "worth a look")
        case .high: return String(localized: "session.level.high", defaultValue: "high risk")
        }
    }

    /// "3 s", "2 min", "1 h 04".
    static func duration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s < 60 { return "\(s) s" }
        if s < 3600 { return s % 60 == 0 || s >= 600 ? "\(s / 60) min" : "\(s / 60) min \(s % 60) s" }
        return String(format: "%d h %02d", s / 3600, (s % 3600) / 60)
    }

    /// The shortest end of each path that tells it apart from the others ("App/State.swift").
    static func shortPaths(_ paths: [String]) -> [String: String] {
        var out: [String: String] = [:]
        let split = paths.map { $0.split(separator: "/").map(String.init) }
        for (i, parts) in split.enumerated() {
            var n = 1
            while n < parts.count {
                let tail = parts.suffix(n)
                let clash = split.enumerated().contains { j, other in j != i && other.suffix(n) == tail }
                if !clash { break }
                n += 1
            }
            out[paths[i]] = parts.suffix(max(n, min(2, parts.count))).joined(separator: "/")
        }
        return out
    }

    private func label(_ title: String) -> some View {
        Text(verbatim: title.uppercased())
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundColor(Color(hex: "#6B7079"))
            .lineLimit(1)
    }

    private func tag(_ text: String, _ hex: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(Color(hex: hex))
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(Color(hex: "#1D1F23")))
    }

    private func shortcut(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 8.5, weight: .semibold))
                Text(verbatim: title).font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(Color(hex: "#9CA1AA"))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private extension String {
    func ifEmpty(_ other: String) -> String { isEmpty ? other : self }
}
