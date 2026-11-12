#if !APPSTORE
import SwiftUI

// MARK: - The Today page: the day's timeline and the week's cost
// Both read TurnLog (one line per finished turn, on this Mac). The timeline puts each turn on
// the day, a row per project, coloured by the guard's worst rating, with the prayers above;
// a click shows the turn. The week sums the tokens per project, beside the Claude plan.

struct TodayTimelineCard: View {
    @ObservedObject private var log = TurnLog.shared
    @ObservedObject private var prayer = PrayerController.shared
    let now: Date
    @State private var selected: UUID?

    var body: some View {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: now)
        let turns = log.turns(from: dayStart)
        let first = turns.map(\.startedAt).min() ?? now.addingTimeInterval(-3600)
        // From the first turn (at the latest 08:00) to now.
        let start = min(first, cal.date(bySettingHour: 8, minute: 0, second: 0, of: now) ?? first)
        let span = max(now.timeIntervalSince(start), 3600)
        let projects = Dictionary(grouping: turns, by: \.project).sorted { $0.value.count > $1.value.count }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "today.timeline", defaultValue: "Today's timeline"))
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                let added = turns.reduce(0) { $0 + $1.added }, removed = turns.reduce(0) { $0 + $1.removed }
                Text(verbatim: String(format: String(localized: "today.timeline.sum %lld", defaultValue: "%lld turns"), Int64(turns.count))
                     + (added + removed > 0 ? " · +\(added) −\(removed)" : ""))
                    .font(.system(size: 12)).foregroundColor(HubTheme.secondary)
            }
            if turns.isEmpty {
                Text(String(localized: "today.timeline.empty", defaultValue: "No agent turn yet today."))
                    .font(.system(size: 13)).foregroundColor(HubTheme.secondary)
            } else {
                GeometryReader { geo in
                    let width = geo.size.width - 110
                    VStack(alignment: .leading, spacing: 8) {
                        // The prayers of the day, above the rows.
                        ZStack(alignment: .topLeading) {
                            Color.clear.frame(height: 14)
                            ForEach(Prayer.allCases.filter(\.isObligatory), id: \.self) { p in
                                if let t = prayer.today?.time(p), t >= start, t <= now {
                                    Text(verbatim: "☾ " + PrayerController.name(p))
                                        .font(.system(size: 10, weight: .semibold)).foregroundColor(RafiqLook.gold)
                                        .fixedSize()
                                        .offset(x: 110 + width * CGFloat(t.timeIntervalSince(start) / span) - 6)
                                }
                            }
                        }
                        ForEach(projects.prefix(5), id: \.key) { project, rows in
                            HStack(spacing: 0) {
                                Text(verbatim: project).font(.system(size: 12)).foregroundColor(HubTheme.body)
                                    .lineLimit(1).frame(width: 110, alignment: .leading)
                                ZStack(alignment: .leading) {
                                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 2)
                                    ForEach(rows) { r in
                                        let on = selected == r.id
                                        Circle().fill(Self.color(r))
                                            .frame(width: on ? 14 : 10, height: on ? 14 : 10)
                                            .overlay(Circle().stroke(Color.white, lineWidth: on ? 2 : 0))
                                            .offset(x: width * CGFloat(r.startedAt.timeIntervalSince(start) / span) - (on ? 7 : 5))
                                            .onTapGesture { selected = on ? nil : r.id }
                                            .help(r.prompt)
                                    }
                                }
                                .frame(width: width, height: 16, alignment: .leading)
                            }
                        }
                    }
                }
                .frame(height: CGFloat(22 + min(projects.count, 5) * 24))
                if let r = turns.first(where: { $0.id == selected }) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: "\(prayer.clock(r.startedAt)) · \(SessionFullView.duration(r.endedAt.timeIntervalSince(r.startedAt))) · \(r.project)")
                            .font(.system(size: 12)).foregroundColor(HubTheme.secondary)
                        Text(verbatim: "« \(r.prompt) »").font(.system(size: 13))
                        Text(verbatim: [
                            r.files > 0 ? SessionDetailsView.filesLabel(r.files) + " · +\(r.added) −\(r.removed)" : nil,
                            r.tokens.map { String(format: String(localized: "details.tokens %@", defaultValue: "%@ tokens"), Self.compact($0)) },
                            r.model,
                            r.stopped ? String(localized: "details.stopped", defaultValue: "Stopped") : nil,
                        ].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 12)).foregroundColor(HubTheme.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(HubTheme.card))
    }

    static func color(_ r: TurnRecord) -> Color {
        if r.stopped { return Color(hex: "#8E939C") }
        return RiskBadge.color(CommandRisk.Level(rawValue: r.worst) ?? .safe)
    }

    /// 1840 → "1.8 k", 2_300_000 → "2.3 M".
    static func compact(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1f M", Double(n) / 1_000_000) }
        if n >= 1000 { return "\(Int((Double(n) / 1000).rounded())) k" }
        return "\(n)"
    }
}

struct WeekCostCard: View {
    struct Row { let project: String; let tokens: Int; let count: Int }

    static func rows(_ turns: [TurnRecord]) -> [Row] {
        var rows: [Row] = []
        for (project, list) in Dictionary(grouping: turns, by: { $0.project }) {
            let tokens: Int = list.reduce(0) { $0 + ($1.tokens ?? 0) }
            rows.append(Row(project: project, tokens: tokens, count: list.count))
        }
        return rows.sorted { a, b in a.tokens == b.tokens ? a.count > b.count : a.tokens > b.tokens }
    }

    @ObservedObject private var log = TurnLog.shared
    @ObservedObject private var state = AppState.shared
    let now: Date

    var body: some View {
        let turns = log.turns(from: now.addingTimeInterval(-7 * 86_400))
        let byProject = Self.rows(turns)
        let total = max(1, byProject.reduce(0) { $0 + $1.tokens })
        let costliest = turns.filter { $0.tokens != nil }.max { ($0.tokens ?? 0) < ($1.tokens ?? 0) }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "today.week", defaultValue: "This week, per project"))
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if let usage = state.claudePlanUsage, let pct = ClaudePlanGauge.dominantPct(usage) {
                    Text(verbatim: String(format: String(localized: "today.week.plan %lld", defaultValue: "Claude plan: %lld %% used"), Int64(pct.rounded())))
                        .font(.system(size: 12)).foregroundColor(HubTheme.secondary)
                }
            }
            if byProject.isEmpty {
                Text(String(localized: "today.week.empty", defaultValue: "Nothing yet: each finished turn adds up here."))
                    .font(.system(size: 13)).foregroundColor(HubTheme.secondary)
            }
            ForEach(byProject.prefix(5), id: \.project) { row in
                HStack(spacing: 10) {
                    Text(verbatim: row.project).font(.system(size: 12)).foregroundColor(HubTheme.body)
                        .lineLimit(1).frame(width: 110, alignment: .leading)
                    GeometryReader { geo in
                        Capsule().fill(RafiqLook.gold.opacity(0.75))
                            .frame(width: max(4, geo.size.width * CGFloat(row.tokens) / CGFloat(total)), height: 6)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                    .frame(height: 14)
                    Text(verbatim: "\(TodayTimelineCard.compact(row.tokens)) · " + String(format: String(localized: "today.timeline.sum %lld", defaultValue: "%lld turns"), Int64(row.count)))
                        .font(.system(size: 12)).monospacedDigit().foregroundColor(HubTheme.secondary)
                        .frame(width: 130, alignment: .trailing)
                }
            }
            if let c = costliest, let t = c.tokens {
                Text(verbatim: String(format: String(localized: "today.week.costliest %@ %@", defaultValue: "Costliest turn: « %@ » · %@ tokens"),
                                      String(c.prompt.prefix(50)), TodayTimelineCard.compact(t)))
                    .font(.system(size: 12)).foregroundColor(HubTheme.secondary).lineLimit(1)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(HubTheme.card))
    }
}
#endif
