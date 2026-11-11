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

/// The coloured line under the resting island.
struct NotchHalo: View {
    @ObservedObject var state: AppState
    @ObservedObject private var prayer = PrayerController.shared
    let islandW: CGFloat
    let islandH: CGFloat

    var body: some View {
        let resting = state.mode != .expanded && !state.islandPlacement.isCorner
        let signal = resting ? NotchLive.signal(state: state, prayer: prayer) : nil
        let width = min(120, max(60, islandW * 0.5))
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
                        Text(verbatim: prayer.pillLabel(at: tl.date))
                            .font(.system(size: fontSize, weight: .semibold))
                            .foregroundColor(soon.isNow ? Color(hex: "#F5F6F8") : RafiqLook.gold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(width: max(0, side - 62), alignment: .leading)
                    .position(x: 56 + max(0, side - 62) / 2, y: islandH / 2)
                    .transition(.opacity)
                }
                // Right: between the notch and the mini Rafiqs.
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
        if state.activeIntegrations.contains(PrayerController.pillId), prayer.location != nil {
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
/// an approval waits.
struct HeaderGuardShield: View {
    @ObservedObject var state: AppState

    var body: some View {
        let risk = state.pendingApproval.flatMap { a in
            a.tool == "ExitPlanMode" ? nil : CommandRisk.assess(tool: a.tool, command: a.command)
        }
        let color = risk.map { RiskBadge.color($0.level) } ?? Color(hex: "#34D399")
        Image(systemName: risk?.level == .high ? "exclamationmark.shield.fill" : "checkmark.shield")
            .font(.system(size: 14))
            .foregroundColor(color.opacity(risk == nil ? 0.75 : 1))
            .help(String(localized: "guard.help", defaultValue: "Agent guard: rates the risk of every action an agent asks for. It never answers for you."))
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
