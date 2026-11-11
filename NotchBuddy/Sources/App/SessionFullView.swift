import SwiftUI

/// "Details": the open island grows to show the whole turn of the focused session — every
/// step with the guard's rating, the files changed, the Git state, the guard's tally and
/// the shortcuts. Opened from the session card; folds back like any open island.
struct SessionFullView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var riskLog = CommandRiskLog.shared
    @ObservedObject private var git = GitStatusStore.shared

    var body: some View {
        ZStack(alignment: .topLeading) {
            CardBackground(wash: nil)
            if let task = state.focusTask {
                content(task)
                    .padding(.leading, 108)
                    .padding(.trailing, 16)
                    .padding(.vertical, 12)
            }
        }
    }

    private func content(_ task: AgentTask) -> some View {
        let entries = riskLog.entries(for: task)
        let diffs = state.sessionDiffs[task.pill] ?? []
        var byFile: [(path: String, added: Int, removed: Int)] = []
        for d in diffs {
            if let i = byFile.firstIndex(where: { $0.path == d.path }) {
                byFile[i].added += d.added; byFile[i].removed += d.removed
            } else {
                byFile.append((d.path, d.added, d.removed))
            }
        }
        let summary = git.summary(for: task.sessionCwd)
        let tally = Dictionary(grouping: entries, by: { $0.risk.level }).mapValues(\.count)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(Color(hex: task.color)).frame(width: 8, height: 8)
                Text(verbatim: task.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                if let cwd = task.sessionCwd, !cwd.isEmpty {
                    Text(verbatim: "· " + (cwd as NSString).abbreviatingWithTildeInPath)
                        .font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C")).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 4)
                Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { state.view = .overview } }) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundColor(Color(hex: "#6B7079"))
                        .frame(width: 18, height: 18).background(Color.white.opacity(0.06)).clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            HStack(alignment: .top, spacing: 14) {
                // Steps
                VStack(alignment: .leading, spacing: 4) {
                    section(String(format: String(localized: "session.steps %lld", defaultValue: "Steps of the turn · %lld"), Int64(entries.count)))
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(entries) { e in
                                    HStack(spacing: 8) {
                                        Circle().fill(RiskBadge.color(e.risk.level)).frame(width: 6, height: 6)
                                        Text(verbatim: e.label).font(.system(size: 11)).foregroundColor(Color(hex: "#C0C4CC"))
                                            .lineLimit(1).truncationMode(.tail)
                                        Spacer(minLength: 4)
                                        Text(verbatim: e.risk.reason.label).font(.system(size: 9.5, weight: .semibold))
                                            .foregroundColor(RiskBadge.color(e.risk.level)).lineLimit(1).fixedSize()
                                    }
                                    .padding(.vertical, 4)
                                    .overlay(Rectangle().fill(Color.white.opacity(0.05)).frame(height: 0.5), alignment: .top)
                                    .id(e.id)
                                }
                                if entries.isEmpty {
                                    Text(String(localized: "session.no-steps", defaultValue: "No step rated yet in this turn."))
                                        .font(.system(size: 11)).foregroundColor(Color(hex: "#6B7079"))
                                }
                            }
                        }
                        .onAppear { if let last = entries.last { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Files, Git, guard, shortcuts
                VStack(alignment: .leading, spacing: 4) {
                    section(String(localized: "session.files-changed", defaultValue: "Files changed"))
                    if byFile.isEmpty {
                        Text(verbatim: "—").font(.system(size: 11)).foregroundColor(Color(hex: "#6B7079"))
                    }
                    ForEach(byFile.prefix(6), id: \.path) { f in
                        HStack(spacing: 6) {
                            Text(verbatim: (f.path as NSString).lastPathComponent)
                                .font(.system(size: 10.5, design: .monospaced)).foregroundColor(Color(hex: "#C0C4CC"))
                                .lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 2)
                            Text(verbatim: "+\(f.added)").foregroundColor(Color(hex: "#34D399"))
                            Text(verbatim: "−\(f.removed)").foregroundColor(Color(hex: "#F4505E"))
                        }
                        .font(.system(size: 10.5, weight: .semibold))
                    }
                    if let g = summary {
                        section("Git").padding(.top, 6)
                        HStack(spacing: 5) {
                            tag("⎇ \(g.branch)", "#C0C4CC")
                            if g.ahead > 0 { tag(String(format: String(localized: "session.unpushed %lld", defaultValue: "↑ %lld not pushed"), Int64(g.ahead)), "#F5A524") }
                            if g.changed > 0 { tag("● \(g.changed)", "#C0C4CC") }
                        }
                    }
                    section(String(localized: "watch.guard", defaultValue: "Guard")).padding(.top, 6)
                    ForEach([CommandRisk.Level.safe, .caution, .high], id: \.self) { level in
                        HStack(spacing: 6) {
                            Circle().fill(RiskBadge.color(level)).frame(width: 6, height: 6)
                            Text(verbatim: "\(tally[level] ?? 0) " + Self.levelName(level))
                                .font(.system(size: 10.5)).foregroundColor(Color(hex: "#9CA1AA"))
                        }
                    }
                }
                .frame(width: 190, alignment: .topLeading)
            }
        }
        .onAppear { git.refresh(task.sessionCwd) }
    }

    static func levelName(_ level: CommandRisk.Level) -> String {
        switch level {
        case .safe: return String(localized: "session.level.safe", defaultValue: "read only")
        case .caution: return String(localized: "session.level.caution", defaultValue: "worth a look")
        case .high: return String(localized: "session.level.high", defaultValue: "high risk")
        }
    }

    private func section(_ title: String) -> some View {
        Text(verbatim: title.uppercased())
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundColor(Color(hex: "#6B7079"))
    }

    private func tag(_ text: String, _ hex: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(Color(hex: hex))
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(Color(hex: "#1D1F23")))
    }
}
