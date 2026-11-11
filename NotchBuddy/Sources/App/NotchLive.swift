import SwiftUI

// MARK: - What the notch says without opening
// Two glanceable layers on the resting island (spec §2 bis):
// - the halo, a short coloured line under the notch, hidden or compact: an agent waiting
//   (orange), an error (red), a prayer coming (gold), a task just finished (green);
// - the ears, one word on each side of the compact island: the coming prayer on the left,
//   the most urgent agent news on the right. The island grows by `NotchEars.extra` for them.
// Both are drawn from published state only: no timer while hidden (CLAUDE.md, 0 % CPU).
// The prayer countdown in the ear redraws once a minute, and only while it is on screen.

enum NotchSignal: Equatable {
    case approval, error, prayer, finished

    var color: Color {
        switch self {
        case .approval: return Color(hex: "#F07A3A")
        case .error:    return Color(hex: "#F4505E")
        case .prayer:   return RafiqLook.gold
        case .finished: return Color(hex: "#34D399")
        }
    }
}

@MainActor
enum NotchLive {
    /// The most urgent thing on the island now, if any.
    static func signal(state: AppState, prayer: PrayerController) -> NotchSignal? {
        if state.pendingApproval != nil || state.pendingQuestion != nil { return .approval }
        let agents = state.tasks.filter { !$0.isIntegration }
        if agents.contains(where: { $0.state == .approval || $0.state == .question }) { return .approval }
        if agents.contains(where: { $0.state == .error }) { return .error }
        if prayer.soon != nil { return .prayer }
        if agents.contains(where: { $0.state == .finished }) { return .finished }
        return nil
    }

    /// The right ear: the agent news worth a word, if any.
    static func agentWord(state: AppState) -> (text: String, color: Color)? {
        let waiting = (state.pendingApproval?.queueCount ?? 0)
            + state.waitingQuestions.count
        if waiting > 1 {
            return (String(format: String(localized: "notch.ear.waiting-count %lld", defaultValue: "%lld waiting"), waiting),
                    NotchSignal.approval.color)
        }
        if waiting == 1 || state.pendingApproval != nil || state.pendingQuestion != nil {
            return (String(localized: "notch.ear.waiting", defaultValue: "Waiting for you"), NotchSignal.approval.color)
        }
        let agents = state.tasks.filter { !$0.isIntegration }
        if agents.contains(where: { $0.state == .error }) {
            return (String(localized: "notch.ear.error", defaultValue: "Error"), NotchSignal.error.color)
        }
        if agents.contains(where: { $0.state == .finished }) {
            return (String(localized: "notch.ear.done", defaultValue: "Done"), NotchSignal.finished.color)
        }
        return nil
    }

    /// The ears have something to say: the compact island widens for them.
    static func earsActive(state: AppState, prayer: PrayerController) -> Bool {
        prayer.soon != nil || agentWord(state: state) != nil
    }

    /// Keeps `NotchEars.extra` (read by islandSize) in step with what the ears say.
    static func refreshEars(state: AppState, prayer: PrayerController) {
        let on = !state.islandPlacement.isCorner && earsActive(state: state, prayer: prayer)
        NotchEars.extra = on ? NotchEars.width : 0
    }
}

/// How much wider the compact island is while the ears speak (both sides together).
enum NotchEars {
    nonisolated(unsafe) static var extra: CGFloat = 0
    static let width: CGFloat = 150
}

// MARK: - Halo

/// The coloured line under the island (resting or open; not in a corner, where the tile floats).
struct NotchHalo: View {
    @ObservedObject var state: AppState
    @ObservedObject private var prayer = PrayerController.shared
    let islandW: CGFloat
    let islandH: CGFloat

    var body: some View {
        let shown = !state.islandPlacement.isCorner
        let signal = shown ? NotchLive.signal(state: state, prayer: prayer) : nil
        let width = state.mode == .expanded ? 160 : min(120, max(60, islandW * 0.5))
        ZStack {
            if let signal {
                Capsule()
                    .fill(signal.color)
                    .frame(width: width, height: 3)
                    .shadow(color: signal.color.opacity(0.7), radius: 4)
                    .transition(.opacity.combined(with: .scale(scale: 0.4, anchor: .center)))
                    .id(signal)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.72), value: signal)
        .animation(.spring(response: 0.5, dampingFraction: 0.72), value: width)
        .position(x: islandW / 2, y: islandH + 4)
        .allowsHitTesting(false)
    }
}

// MARK: - Ears

/// One word on each side of the compact island.
struct NotchEarsView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var prayer = PrayerController.shared
    let islandW: CGFloat
    let islandH: CGFloat

    var body: some View {
        let show = state.mode == .compact && !state.islandPlacement.isCorner && NotchEars.extra > 0
        let side = max(0, (islandW - state.notchWidth) / 2)
        let fontSize: CGFloat = min(11, max(8, islandH - 18))
        ZStack(alignment: .topLeading) {
            if show {
                // Left: Rafiq stays at x 40; the word sits between him and the notch.
                if let soon = prayer.soon {
                    TimelineView(.everyMinute) { tl in
                        Text(verbatim: prayer.earLabel(at: tl.date))
                            .font(.system(size: fontSize, weight: .semibold))
                            .foregroundColor(soon.isNow ? Color(hex: "#F5F6F8") : RafiqLook.gold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(width: max(0, side - 62), alignment: .leading)
                    .position(x: 56 + max(0, side - 62) / 2, y: islandH / 2)
                    .transition(.opacity)
                }
                // Right: between the notch and the mini Rafiqs. In Ramadan, with nothing from the
                // agents, the day of the month.
                if NotchLive.agentWord(state: state) == nil, let soon = prayer.soon, soon.ramadan {
                    let day = prayer.hijriMonthDay(at: Date()).day
                    Text(verbatim: String(format: String(localized: "ramadan.day %lld", defaultValue: "Day %lld / 30"), day))
                        .font(.system(size: fontSize, weight: .semibold))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .lineLimit(1)
                        .frame(width: max(0, side - 66), alignment: .leading)
                        .position(x: islandW - side + 8 + max(0, side - 66) / 2, y: islandH / 2)
                        .transition(.opacity)
                }
                if let word = NotchLive.agentWord(state: state) {
                    HStack(spacing: 5) {
                        Circle().fill(word.color).frame(width: 6, height: 6)
                        Text(verbatim: word.text)
                            .font(.system(size: fontSize, weight: .semibold))
                            .foregroundColor(Color(hex: "#F5F6F8"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(width: max(0, side - 66), alignment: .leading)
                    .position(x: islandW - side + 8 + max(0, side - 66) / 2, y: islandH / 2)
                    .transition(.opacity)
                }
            }
        }
        .frame(width: islandW, height: islandH, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.25).delay(show ? 0.22 : 0), value: show)
        .allowsHitTesting(false)
    }
}

// MARK: - Header: prayer chip and the guard's shield

/// The next prayer in the open island's header (left, after the tabs), when it fits.
struct HeaderPrayerChip: View {
    @ObservedObject var state: AppState
    @ObservedObject private var prayer = PrayerController.shared
    @State private var hovered = false

    var body: some View {
        // On the home view the prayer strip already says it: the chip shows on the other views.
        if state.activeIntegrations.contains(PrayerController.pillId), prayer.location != nil,
           !(state.view == .overview && PrayerStripLayout.isOn(state: state, prayer: prayer)) {
            TimelineView(.everyMinute) { tl in
                // Longest first: "☾ Fajr 05:26", "Fajr 05:26", "☾ 05:26", nothing.
                ViewThatFits(in: .horizontal) {
                    chip(prayer.pillLabel(at: tl.date), moon: true)
                    chip(prayer.pillLabel(at: tl.date), moon: false)
                    if let next = prayer.next(at: tl.date) {
                        chip(prayer.clock(next.at), moon: true)
                    }
                    Color.clear.frame(width: 0, height: 0)
                }
            }
        }
    }

    private func chip(_ text: String, moon: Bool) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                state.focusId = PrayerController.pillId
                state.view = .overview
            }
        }) {
            HStack(spacing: 4) {
                if moon {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 9))
                        .foregroundColor(RafiqLook.gold)
                }
                Text(verbatim: text)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(hovered ? RafiqLook.gold : Color(hex: "#C9CDD3"))
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, moon ? 8 : 7)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color(hex: "#0E0F11")))
            .overlay(Capsule().stroke(RafiqLook.gold.opacity(hovered ? 0.55 : 0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovered = $0 }
    }
}

/// The agent guard in the header: green while nothing risky waits, the risk's colour when
/// an approval waits. With room (no plan pill beside it), its name too.
struct HeaderGuardShield: View {
    @ObservedObject var state: AppState
    var showLabel: Bool = false

    var body: some View {
        let risk = state.pendingApproval.flatMap { a in
            a.tool == "ExitPlanMode" ? nil : CommandRisk.assess(tool: a.tool, command: a.command)
        }
        let color = risk.map { RiskBadge.color($0.level) } ?? Color(hex: "#34D399")
        HStack(spacing: 4) {
            Image(systemName: risk?.level == .high ? "exclamationmark.shield.fill" : "checkmark.shield")
                .font(.system(size: 14))
            if showLabel {
                Text(String(localized: "guard.title", defaultValue: "Guard"))
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .foregroundColor(color.opacity(risk == nil ? 0.8 : 1))
        .help(String(localized: "guard.help", defaultValue: "Agent guard: rates the risk of every action an agent asks for. It never answers for you."))
    }
}

// MARK: - The last action of each session, rated

/// The guard's rating of each tool a pill's session ran this turn (PreToolUse): the last one
/// for the badge, the last 16 for the card's step strip, and when the turn began.
/// A new prompt starts a new turn; Stop clears the badge only. Written by HookServer.
@MainActor
final class CommandRiskLog: ObservableObject {
    static let shared = CommandRiskLog()
    @Published private(set) var last: [String: CommandRisk] = [:]
    @Published private(set) var history: [String: [CommandRisk]] = [:]
    @Published private(set) var started: [String: Date] = [:]

    static let historyLength = 16

    /// A new prompt: a new turn, a fresh strip.
    func beginTurn(pill: String) {
        history[pill] = []
        started[pill] = Date()
        last[pill] = nil
    }

    func record(pill: String, tool: String, input: [String: Any]) {
        let command = input["command"] as? String ?? tool
        let risk = CommandRisk.assess(tool: tool, command: command)
        if last[pill] != risk { last[pill] = risk }
        if started[pill] == nil { started[pill] = Date() }
        var h = history[pill] ?? []
        h.append(risk)
        if h.count > Self.historyLength { h.removeFirst(h.count - Self.historyLength) }
        history[pill] = h
    }

    func clear(pill: String) {
        if last[pill] != nil { last[pill] = nil }
    }

    func risk(for task: AgentTask) -> CommandRisk? { last[task.id] ?? last[task.pill] }
    func steps(for task: AgentTask) -> [CommandRisk] { history[task.id] ?? history[task.pill] ?? [] }
    func start(for task: AgentTask) -> Date? { started[task.id] ?? started[task.pill] }
}

// MARK: - Prayer strip (open island, home view)

/// How much taller the home view is: for the prayer strip at the top of its right card, and
/// for the session card's details (time, place, steps, Git, shortcuts) when an agent is shown.
enum PrayerStripLayout {
    nonisolated(unsafe) static var extra: CGFloat = 0
    static let height: CGFloat = 70

    /// On while the Prayer pill is on and knows where the user is (not in a corner).
    @MainActor static func isOn(state: AppState, prayer: PrayerController) -> Bool {
        !state.islandPlacement.isCorner
            && state.activeIntegrations.contains(PrayerController.pillId)
            && prayer.location != nil && prayer.today != nil
    }

    /// The focused pill is an agent session (not an integration): its card shows details.
    @MainActor static func showsSession(state: AppState) -> Bool {
        guard !state.islandPlacement.isCorner, let t = state.focusTask,
              let category = PillCatalog.definition(for: t.pill)?.category,
              category == .workspace || category == .agent else { return false }
        // Same test as the card's session layout: something ran or is running.
        return t.state != .idle || !t.steps.isEmpty
    }

    /// The home view is taller: prayer strip or session details.
    @MainActor static func isTall(state: AppState, prayer: PrayerController) -> Bool {
        isOn(state: state, prayer: prayer) || showsSession(state: state)
    }

    @MainActor static func refresh(state: AppState, prayer: PrayerController) {
        extra = isTall(state: state, prayer: prayer) ? height : 0
    }
}

/// The day's prayers above the pills: the next one (a countdown at night), the short Hijri
/// date in Arabic, the qibla, the sun on its arc, then the five times, checked once prayed.
/// Tap the header: the Prayer card. Tap the beads: the tasbih.
struct PrayerStripView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var prayer = PrayerController.shared

    var body: some View {
        TimelineView(.everyMinute) { tl in
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            state.focusId = PrayerController.pillId
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "moon.fill")
                                .font(.system(size: 9))
                                .foregroundColor(RafiqLook.gold)
                            Text(verbatim: headline(at: tl.date))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(RafiqLook.gold)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 4)
                    Text(verbatim: prayer.hijriShortArabic(at: tl.date))
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .lineLimit(1)
                    if let qibla = prayer.qibla {
                        HStack(spacing: 2) {
                            Image(systemName: "location.north.fill")
                                .font(.system(size: 8))
                                .rotationEffect(.degrees(qibla))
                                .foregroundColor(RafiqLook.gold)
                            Text(verbatim: "\(Int(qibla.rounded()))°")
                                .font(.system(size: 10, weight: .semibold))
                                .monospacedDigit()
                                .foregroundColor(Color(hex: "#8E939C"))
                        }
                        .help(String(format: String(localized: "qibla.help %lld", defaultValue: "Qibla: %lld° from north"),
                                     Int64(qibla.rounded())))
                    }
                    Button(action: { TasbihCounter.shared.open() }) {
                        Image(systemName: "circle.hexagonpath")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(RafiqLook.gold)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(RafiqLook.gold.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "tasbih.open", defaultValue: "Tasbih"))
                }
                if let today = prayer.today {
                    PrayerSunArc(day: today, date: tl.date, accent: RafiqLook.gold)
                        .frame(height: 12)
                    times(today, at: tl.date)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 7)
        }
    }

    /// Day: "Asr 15:42" (or the pill's countdown). Night: "Fajr · in 6 h 12 min".
    private func headline(at date: Date) -> String {
        guard let today = prayer.today, let next = prayer.next(at: date) else { return prayer.pillLabel(at: date) }
        if PrayerTimesEngine.sunProgress(at: date, day: today) == nil {
            return "\(PrayerController.name(next.prayer)) · "
                + String(format: String(localized: "prayer.in %@", defaultValue: "in %@"),
                         PrayerController.countdown(next.at.timeIntervalSince(date)))
        }
        return prayer.pillLabel(at: date)
    }

    /// The five times, the next one in gold, the ones prayed with a tick (tap to tick).
    private func times(_ day: PrayerDay, at date: Date) -> some View {
        let next = prayer.next(at: date)?.prayer
        return HStack(spacing: 0) {
            ForEach(Prayer.obligatory, id: \.self) { p in
                let isNext = p == next
                let done = prayer.prayed.contains(p)
                Button(action: { prayer.togglePrayed(p) }) {
                    VStack(spacing: 0) {
                        HStack(spacing: 2) {
                            Text(verbatim: PrayerController.name(p))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            if done {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 6, weight: .bold))
                            }
                        }
                        .font(.system(size: 8.5, weight: isNext ? .semibold : .regular))
                        Text(verbatim: day.time(p).map { prayer.clock($0) } ?? "—")
                            .font(.system(size: 9.5, weight: isNext ? .semibold : .regular))
                            .monospacedDigit()
                    }
                    .foregroundColor(isNext ? RafiqLook.gold : (done ? Color(hex: "#8E939C") : Color(hex: "#6B7079")))
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Risk badge

/// "Read only", "Deletes", "Force push"…: the guard's rating on the approval card.
struct RiskBadge: View {
    let risk: CommandRisk

    var body: some View {
        let color = Self.color(risk.level)
        HStack(spacing: 3) {
            Image(systemName: Self.icon(risk.level))
                .font(.system(size: 8, weight: .bold))
            Text(verbatim: Self.label(risk.reason))
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundColor(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(color.opacity(0.14)))
        .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 1))
        .help(String(localized: "guard.help", defaultValue: "Agent guard: rates the risk of every action an agent asks for. It never answers for you."))
    }

    /// One line saying what the action can do, under the command on the approval card.
    static func explanation(_ reason: CommandRisk.Reason) -> String {
        switch reason {
        case .readOnly:        return String(localized: "guard.why.read-only", defaultValue: "Changes nothing")
        case .writesFiles:     return String(localized: "guard.why.writes", defaultValue: "Changes files in the project")
        case .network:         return String(localized: "guard.why.network", defaultValue: "Talks to a server")
        case .installs:        return String(localized: "guard.why.installs", defaultValue: "Adds packages to the machine")
        case .runsCode:        return String(localized: "guard.why.runs-code", defaultValue: "Starts a program")
        case .publishes:       return String(localized: "guard.why.publishes", defaultValue: "Sends your work outside")
        case .unknown:         return String(localized: "guard.why.unknown", defaultValue: "A command the guard does not know")
        case .deletes:         return String(localized: "guard.why.deletes", defaultValue: "Can erase files for good")
        case .forcePush:       return String(localized: "guard.why.force-push", defaultValue: "Rewrites the remote history")
        case .rewritesHistory: return String(localized: "guard.why.history", defaultValue: "Rewrites the Git history")
        case .pipeToShell:     return String(localized: "guard.why.pipe", defaultValue: "Runs a script straight from the internet")
        case .privilege:       return String(localized: "guard.why.admin", defaultValue: "Asks for administrator rights")
        case .secrets:         return String(localized: "guard.why.secrets", defaultValue: "Touches keys, tokens or passwords")
        case .systemConfig:    return String(localized: "guard.why.system", defaultValue: "Changes how the Mac works")
        }
    }

    static func color(_ level: CommandRisk.Level) -> Color {
        switch level {
        case .safe:    return Color(hex: "#34D399")
        case .caution: return Color(hex: "#F5A524")
        case .high:    return Color(hex: "#F4505E")
        }
    }

    static func icon(_ level: CommandRisk.Level) -> String {
        switch level {
        case .safe:    return "checkmark.shield.fill"
        case .caution: return "eye.fill"
        case .high:    return "exclamationmark.triangle.fill"
        }
    }

    static func label(_ reason: CommandRisk.Reason) -> String {
        switch reason {
        case .readOnly:        return String(localized: "guard.reason.read-only", defaultValue: "Read only")
        case .writesFiles:     return String(localized: "guard.reason.writes", defaultValue: "Edits files")
        case .network:         return String(localized: "guard.reason.network", defaultValue: "Network")
        case .installs:        return String(localized: "guard.reason.installs", defaultValue: "Installs")
        case .runsCode:        return String(localized: "guard.reason.runs-code", defaultValue: "Runs code")
        case .publishes:       return String(localized: "guard.reason.publishes", defaultValue: "Publishes")
        case .unknown:         return String(localized: "guard.reason.unknown", defaultValue: "Check it")
        case .deletes:         return String(localized: "guard.reason.deletes", defaultValue: "Deletes")
        case .forcePush:       return String(localized: "guard.reason.force-push", defaultValue: "Force push")
        case .rewritesHistory: return String(localized: "guard.reason.history", defaultValue: "Rewrites history")
        case .pipeToShell:     return String(localized: "guard.reason.pipe", defaultValue: "Runs downloaded code")
        case .privilege:       return String(localized: "guard.reason.admin", defaultValue: "Admin rights")
        case .secrets:         return String(localized: "guard.reason.secrets", defaultValue: "Secrets")
        case .systemConfig:    return String(localized: "guard.reason.system", defaultValue: "System settings")
        }
    }
}

// MARK: - Session details (open card, home view)

/// Under the session's steps: where and for how long it runs, the guard's strip of this turn,
/// what it changed, the project's Git state, and three shortcuts. Shown while the home view is
/// tall for it (PrayerStripLayout.showsSession).
struct SessionDetailsView: View {
    let task: AgentTask
    @ObservedObject var state: AppState
    let openTarget: () -> Void
    @ObservedObject private var riskLog = CommandRiskLog.shared
    @ObservedObject private var git = GitStatusStore.shared
    @ObservedObject private var shield = AgentShield.shared

    var body: some View {
        let diffs = state.sessionDiffs[task.pill] ?? []
        let added = diffs.reduce(0) { $0 + $1.added }
        let removed = diffs.reduce(0) { $0 + $1.removed }
        let files = Set(diffs.map(\.path)).count
        let steps = riskLog.steps(for: task)
        let summary = git.summary(for: task.sessionCwd)
        VStack(alignment: .leading, spacing: 5) {
            TimelineView(.everyMinute) { tl in
                Text(verbatim: placeLine(at: tl.date))
                    .font(.system(size: 10.5))
                    .foregroundColor(Color(hex: "#6B7079"))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if !steps.isEmpty {
                HStack(spacing: 3) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, r in
                        Circle()
                            .fill(RiskBadge.color(r.level))
                            .frame(width: i == steps.count - 1 ? 7 : 5, height: i == steps.count - 1 ? 7 : 5)
                            .help(RiskBadge.label(r.reason))
                    }
                }
                .frame(height: 8)
            }
            HStack(spacing: 5) {
                if task.state == .working, let risk = riskLog.risk(for: task) {
                    RiskBadge(risk: risk)
                }
                if added + removed > 0 {
                    chip {
                        Text(verbatim: "+\(added)").foregroundColor(Color(hex: "#34D399"))
                        Text(verbatim: "−\(removed)").foregroundColor(Color(hex: "#F4505E"))
                    }
                }
                if files > 0 {
                    chip { Text(verbatim: String(format: String(localized: "session.files %lld", defaultValue: "%lld files"), Int64(files))) }
                }
                if let g = summary {
                    chip {
                        Image(systemName: "arrow.triangle.branch").font(.system(size: 8, weight: .semibold))
                        Text(verbatim: g.branch).lineLimit(1)
                        if g.ahead > 0 { Text(verbatim: "↑\(g.ahead)").foregroundColor(Color(hex: "#F5A524")) }
                        if g.changed > 0 { Text(verbatim: "●\(g.changed)") }
                    }
                    .help(gitHelp(g))
                }
            }
            HStack(spacing: 5) {
                shortcut("terminal", String(localized: "session.open-terminal", defaultValue: "Terminal"), action: openTarget)
                if !diffs.isEmpty {
                    shortcut("plusminus", String(localized: "session.last-diff", defaultValue: "Last diff")) {
                        NotificationCenter.default.post(name: .islandToggleDiff, object: nil)
                    }
                }
                if let cwd = task.sessionCwd, !cwd.isEmpty {
                    shortcut("folder", String(localized: "session.folder", defaultValue: "Folder")) {
                        NSWorkspace.shared.open(URL(fileURLWithPath: cwd))
                    }
                    if shield.net(for: cwd) != nil {
                        shortcut("arrow.uturn.backward", String(localized: "net.back", defaultValue: "Back to the net")) {
                            AgentShield.shared.restore(cwd: cwd)
                        }
                    }
                }
            }
        }
        .onAppear { git.refresh(task.sessionCwd) }
    }

    /// "Desktop · ~/Rafiq · 2 h 14 min".
    private func placeLine(at date: Date) -> String {
        var parts: [String] = []
        parts.append(task.pill == "agent_claude-desktop" ? "Claude Desktop" : ClaudeHost.name(for: task.hostApp))
        if let cwd = task.sessionCwd, !cwd.isEmpty {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            parts.append(cwd.hasPrefix(home) ? "~" + cwd.dropFirst(home.count) : cwd)
        }
        if let start = riskLog.start(for: task) {
            parts.append(PrayerController.countdown(date.timeIntervalSince(start)))
        }
        return parts.joined(separator: " · ")
    }

    private func gitHelp(_ g: GitSummary) -> String {
        String(format: String(localized: "session.git-help %@ %lld %lld", defaultValue: "Branch %@ · %lld commits not pushed · %lld files changed"),
               g.branch, Int64(g.ahead), Int64(g.changed))
    }

    private func chip<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 3) { content() }
            .font(.system(size: 10, weight: .semibold))
            .monospacedDigit()
            .foregroundColor(Color(hex: "#C0C4CC"))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
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

// MARK: - Claude plan ring around Rafiq (open island, home view)

#if !APPSTORE
/// The share of the Claude plan used, as a ring around Rafiq on the home view (the header
/// pill stays, and opens the details). Shown only with the plan gauge on.
struct PlanRingView: View {
    @ObservedObject var state: AppState
    let islandW: CGFloat
    let islandH: CGFloat

    var body: some View {
        let on = state.mode == .expanded && state.view == .overview && !state.islandPlacement.isCorner
            && state.showPlanInNotch && state.planRelayInstalled
        let usage = state.demoPlanUsageOverride ?? state.claudePlanUsage
        let pct = usage.flatMap { ClaudePlanGauge.dominantPct($0) }
        let (cx, cy, d, _) = botPosition(mode: .expanded, view: .overview, islandW: islandW, islandH: islandH,
                                         uploadProgress: 0, hasNotch: state.hasNotch)
        let size = d + 30
        ZStack {
            if on, let pct {
                Circle().stroke(Color.white.opacity(0.07), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: min(1, max(0.02, pct / 100)))
                    .stroke(Color(hex: ClaudePlanGauge.color(for: pct)),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: pct)
            }
        }
        .frame(width: size, height: size)
        .position(x: cx, y: cy + 2)
        .opacity(on ? 1 : 0)
        .animation(.easeInOut(duration: 0.25), value: on)
        .allowsHitTesting(false)
    }
}
#endif
