#if !APPSTORE
import AppKit
import SwiftUI

// MARK: - The Tools tab of the island
//
// Rafiq stays on the left as everywhere; on the right, three pages: the installed tools in
// tiles, the Mac (processor, memory, disk, network, battery, what consumes, open ports), and the
// agents' usage (Claude's limits, tokens and their API value).

struct ToolsView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var hub = FeatureHub.shared
    @AppStorage("tools.page") private var page = "tools"
    @Environment(\.islandViewActive) private var active

    private var pages: [(id: String, title: String)] {
        var list = [("tools", String(localized: "tools.page.tools", defaultValue: "Tools"))]
        if hub.isOn(.macMonitor) { list.append(("mac", String(localized: "tools.page.mac", defaultValue: "Mac"))) }
        if hub.isOn(.claudeUsage) { list.append(("usage", String(localized: "tools.page.usage", defaultValue: "Usage"))) }
        return list
    }

    private var shown: String { pages.contains { $0.id == page } ? page : "tools" }

    var body: some View {
        ZStack(alignment: .topLeading) {
            CardBackground(wash: nil)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(pages, id: \.id) { p in
                        Button { withAnimation(.easeInOut(duration: 0.15)) { page = p.id } } label: {
                            Text(p.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(shown == p.id ? RafiqLook.gold : Color(hex: "#8E939C"))
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(shown == p.id ? RafiqLook.gold.opacity(0.14) : Color.white.opacity(0.04))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Button { SettingsOpener.features() } label: {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 11)).foregroundColor(Color(hex: "#6B7079"))
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "tools.manage", defaultValue: "Choose the features"))
                }
                switch shown {
                case "mac": MacPage(active: active)
                case "usage": UsagePage(state: state, active: active)
                default: ToolsGrid()
                }
            }
            .padding(.leading, 112)
            .padding(.trailing, 14)
            .padding(.vertical, 10)
        }
    }
}

enum SettingsOpener {
    @MainActor static func features() {
        FlowHubController.shared.show(.features)
    }
}

// MARK: - Tools grid

private struct ToolsGrid: View {
    @ObservedObject private var hub = FeatureHub.shared
    @ObservedObject private var awake = KeepAwake.shared
    @ObservedObject private var speed = SpeedTest.shared
    @State private var status: String?
    @State private var confirmTrash = false
    @State private var showingApps = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 5)

    var body: some View {
        if showingApps {
            QuitAppsList(back: { showingApps = false })
        } else {
            VStack(alignment: .leading, spacing: 6) {
                LazyVGrid(columns: columns, spacing: 6) {
                    if hub.isOn(.keepAwake) {
                        ToolTile(symbol: "cup.and.saucer", title: String(localized: "tools.awake", defaultValue: "Awake"),
                                 on: awake.active, badge: awake.manualOn ? "1 h" : (awake.active ? "auto" : nil)) {
                            if awake.manualOn { awake.stopManual() } else { awake.keepFor(minutes: 60) }
                        }
                    }
                    if hub.isOn(.quickToggles) {
                        ToolTile(symbol: "circle.lefthalf.filled", title: String(localized: "tools.dark", defaultValue: "Dark mode")) {
                            QuickActions.toggleDarkMode()
                        }
                        ToolTile(symbol: "menubar.dock.rectangle", title: String(localized: "tools.desktop", defaultValue: "Desktop"),
                                 on: QuickActions.desktopIconsHidden) {
                            QuickActions.toggleDesktopIcons()
                        }
                        ToolTile(symbol: "eject", title: String(localized: "tools.eject", defaultValue: "Eject")) {
                            let n = QuickActions.ejectAll()
                            status = n == 0 ? String(localized: "tools.eject.none", defaultValue: "No disk to eject.")
                                : String(format: String(localized: "tools.eject.done %lld", defaultValue: "%lld disks ejected."), n)
                        }
                        ToolTile(symbol: "trash", title: confirmTrash ? String(localized: "tools.trash.confirm", defaultValue: "Sure?")
                                                                      : String(localized: "tools.trash", defaultValue: "Trash"),
                                 on: confirmTrash, badge: QuickActions.trashCount > 0 ? "\(QuickActions.trashCount)" : nil) {
                            if confirmTrash {
                                confirmTrash = false
                                QuickActions.emptyTrash()
                                status = String(localized: "tools.trash.done", defaultValue: "Trash emptied.")
                            } else {
                                confirmTrash = true
                                status = String(localized: "tools.trash.ask", defaultValue: "Click again to empty the Trash for good.")
                            }
                        }
                        ToolTile(symbol: "lock", title: String(localized: "tools.lock", defaultValue: "Lock")) {
                            QuickActions.lockScreen()
                        }
                    }
                    if hub.isOn(.colorPicker) {
                        ToolTile(symbol: "eyedropper", title: String(localized: "tools.color", defaultValue: "Color")) {
                            QuickActions.pickColor { hex in
                                if let hex { status = String(format: String(localized: "tools.color.copied %@", defaultValue: "%@ copied."), hex) }
                            }
                        }
                    }
                    if hub.isOn(.screenText) {
                        ToolTile(symbol: "text.viewfinder", title: String(localized: "tools.text", defaultValue: "Screen text")) {
                            Task {
                                if let text = await QuickActions.textFromScreen() {
                                    let lines = text.split(separator: "\n").count
                                    status = String(format: String(localized: "tools.text.copied %lld", defaultValue: "%lld lines copied."), lines)
                                }
                            }
                        }
                    }
                    if hub.isOn(.speedTest) {
                        ToolTile(symbol: "speedometer", title: speed.running ? String(localized: "tools.speed.running", defaultValue: "Testing…")
                                                                             : String(localized: "tools.speed", defaultValue: "Speed"),
                                 on: speed.running) { speed.run() }
                    }
                    if hub.isOn(.quitApps) {
                        ToolTile(symbol: "xmark.app", title: String(localized: "tools.quit", defaultValue: "Quit apps")) {
                            showingApps = true
                        }
                    }
                }
                if let down = speed.down, !speed.running {
                    Text(verbatim: "↓ \(SpeedTest.mbps(down))" + (speed.up.map { "   ↑ \(SpeedTest.mbps($0))" } ?? ""))
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(Color(hex: "#E1E3E6"))
                }
                if let status {
                    Text(status).font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
                }
                if hub.isOn(.keepAwake) {
                    Toggle(isOn: $awake.whileAgents) {
                        Text(String(localized: "tools.awake.agents", defaultValue: "Keep the Mac awake while an agent works"))
                            .font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
                    }
                    .toggleStyle(.switch).controlSize(.mini)
                }
            }
        }
    }
}

private struct ToolTile: View {
    let symbol: String
    let title: String
    var on = false
    var badge: String? = nil
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 15))
                    .foregroundColor(on ? RafiqLook.gold : Color(hex: "#E1E3E6"))
                Text(title).font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(Color(hex: "#B0B5BE")).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(on ? RafiqLook.gold.opacity(0.12) : Color.white.opacity(hovered ? 0.08 : 0.045))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(on ? RafiqLook.gold.opacity(0.45) : Color.white.opacity(0.06)))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .topTrailing) {
                if let badge {
                    Text(verbatim: badge).font(.system(size: 8.5, weight: .bold)).foregroundColor(.black)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(RafiqLook.gold).clipShape(Capsule()).padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

private struct QuitAppsList: View {
    let back: () -> Void
    @State private var apps: [NSRunningApplication] = QuickActions.openApps

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button(action: back) {
                    Label(String(localized: "tools.back", defaultValue: "Back"), systemImage: "chevron.left")
                        .font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
                }
                .buttonStyle(.plain)
                Spacer()
                SmallButton(String(localized: "tools.quit.others", defaultValue: "All but the front one")) {
                    QuickActions.quitAll(except: true); reload()
                }
                SmallButton(String(localized: "tools.quit.all", defaultValue: "Quit all")) {
                    QuickActions.quitAll(except: false); reload()
                }
            }
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(apps, id: \.processIdentifier) { app in
                        HStack(spacing: 8) {
                            if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 16, height: 16) }
                            Text(verbatim: app.localizedName ?? "?").font(.system(size: 11.5)).foregroundColor(Color(hex: "#E1E3E6"))
                            Spacer()
                            SmallButton(String(localized: "tools.quit.one", defaultValue: "Quit")) { app.terminate(); reload() }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private func reload() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { apps = QuickActions.openApps }
    }
}

struct SmallButton: View {
    let title: String
    let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundColor(Color(hex: "#E1E3E6"))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.white.opacity(0.07)).clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Mac page

private struct MacPage: View {
    let active: Bool
    @ObservedObject private var mac = MacMonitor.shared
    @ObservedObject private var ports = PortWatch.shared
    @ObservedObject private var hub = FeatureHub.shared

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Stat(title: "CPU", value: "\(Int(mac.cpu.rounded())) %")
                    Stat(title: String(localized: "tools.mac.temp", defaultValue: "Temp."),
                         value: mac.cpuTemperature.map { "\(Int($0.rounded()))°" } ?? "—")
                    Stat(title: String(localized: "tools.mac.battery", defaultValue: "Battery"),
                         value: mac.battery.map { "\($0.percent) %" } ?? "—")
                }
                Sparkline(values: mac.cpuHistory, color: Color(hex: "#5EA7F0"))
                    .frame(height: 26)
                Meter(title: String(localized: "tools.mac.memory", defaultValue: "Memory"),
                      share: mac.memoryTotal > 0 ? mac.memoryUsed / mac.memoryTotal : 0,
                      detail: "\(MacMonitor.bytes(mac.memoryUsed)) / \(MacMonitor.bytes(mac.memoryTotal))",
                      color: mac.memoryPressure >= 4 ? "#F4505E" : mac.memoryPressure >= 2 ? "#F59E0B" : "#34D399")
                Meter(title: String(localized: "tools.mac.disk", defaultValue: "Disk"),
                      share: mac.diskUsedShare,
                      detail: String(format: String(localized: "tools.mac.free %@", defaultValue: "%@ free"), MacMonitor.bytes(mac.diskFree)),
                      color: mac.diskUsedShare > 0.9 ? "#F59E0B" : "#5EA7F0")
                HStack {
                    Text(String(localized: "tools.mac.network", defaultValue: "Network")).foregroundColor(Color(hex: "#8E939C"))
                    Spacer()
                    Text(verbatim: "↓ \(MacMonitor.rate(mac.downRate))  ↑ \(MacMonitor.rate(mac.upRate))").foregroundColor(Color(hex: "#E1E3E6"))
                }
                .font(.system(size: 10.5))
                if let b = mac.battery, b.health != nil || b.cycles != nil {
                    Text(verbatim: [b.health.map { String(format: String(localized: "tools.mac.health %lld", defaultValue: "health %lld %%"), $0) },
                                    b.cycles.map { String(format: String(localized: "tools.mac.cycles %lld", defaultValue: "%lld cycles"), $0) }]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 10)).foregroundColor(Color(hex: "#6B7079"))
                }
            }
            .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "tools.mac.top", defaultValue: "Using the processor")).font(.system(size: 10)).foregroundColor(Color(hex: "#6B7079"))
                ForEach(mac.top) { p in
                    HStack {
                        Text(verbatim: p.name).lineLimit(1).foregroundColor(Color(hex: "#E1E3E6"))
                        Spacer()
                        Text(verbatim: "\(Int(p.percent.rounded())) %").foregroundColor(Color(hex: "#8E939C"))
                    }
                    .font(.system(size: 10.5))
                }
                if hub.isOn(.ports) {
                    Text(String(localized: "tools.mac.ports", defaultValue: "Open ports")).font(.system(size: 10)).foregroundColor(Color(hex: "#6B7079"))
                        .padding(.top, 4)
                    if ports.ports.isEmpty {
                        Text(String(localized: "tools.mac.ports.none", defaultValue: "Nothing listens.")).font(.system(size: 10.5)).foregroundColor(Color(hex: "#8E939C"))
                    }
                    ScrollView {
                        VStack(spacing: 3) {
                            ForEach(ports.ports) { port in
                                HStack(spacing: 6) {
                                    Text(verbatim: "\(port.port)").font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                        .foregroundColor(Color(hex: "#E1E3E6"))
                                    Text(verbatim: port.process).lineLimit(1).font(.system(size: 10.5)).foregroundColor(Color(hex: "#8E939C"))
                                    Spacer()
                                    SmallButton(String(localized: "tools.mac.stop", defaultValue: "Stop")) { ports.stop(port) }
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear { if active { start() } }
        .onChange(of: active) { _, now in now ? start() : MacMonitor.shared.stop() }
        .onDisappear { if active { MacMonitor.shared.stop() } }
    }

    private func start() {
        MacMonitor.shared.start()
        if hub.isOn(.ports) { PortWatch.shared.refresh() }
    }
}

private struct Stat: View {
    let title: String
    let value: String
    var body: some View {
        VStack(spacing: 1) {
            Text(title).font(.system(size: 9.5)).foregroundColor(Color(hex: "#6B7079"))
            Text(verbatim: value).font(.system(size: 14, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8"))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 5)
        .background(Color.white.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

private struct Meter: View {
    let title: String
    let share: Double
    let detail: String
    let color: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).foregroundColor(Color(hex: "#8E939C"))
                Spacer()
                Text(verbatim: detail).foregroundColor(Color(hex: "#E1E3E6"))
            }
            .font(.system(size: 10.5))
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(Color(hex: color)).frame(width: g.size.width * min(1, max(0, share)))
                }
            }
            .frame(height: 4)
        }
    }
}

struct Sparkline: View {
    let values: [Double]
    let color: Color
    var body: some View {
        GeometryReader { g in
            Path { path in
                guard values.count > 1 else { return }
                let step = g.size.width / CGFloat(max(values.count - 1, 1))
                for (i, v) in values.enumerated() {
                    let point = CGPoint(x: CGFloat(i) * step, y: g.size.height * (1 - CGFloat(min(100, v) / 100)))
                    if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
        }
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Usage page

private struct UsagePage: View {
    @ObservedObject var state: AppState
    let active: Bool
    @ObservedObject private var ledger = TokenLedger.shared

    private var usage: PlanUsage? { state.demoPlanUsageOverride ?? state.claudePlanUsage }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    ZStack {
                        Ring(share: usage?.fiveHour.map { ClaudePlanGauge.effectivePct($0) / 100 } ?? 0, color: Color(hex: "#E49378"), width: 6)
                            .frame(width: 70, height: 70)
                        Ring(share: usage?.sevenDay.map { ClaudePlanGauge.effectivePct($0) / 100 } ?? 0, color: RafiqLook.gold, width: 6)
                            .frame(width: 50, height: 50)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        WindowLine(title: String(localized: "tools.usage.session", defaultValue: "Session"), window: usage?.fiveHour, color: "#E49378")
                        WindowLine(title: String(localized: "tools.usage.week", defaultValue: "Week"), window: usage?.sevenDay, color: "#E8B64A")
                    }
                }
                if usage == nil {
                    Text(String(localized: "tools.usage.none", defaultValue: "Claude Code didn't answer yet: is it installed and signed in?"))
                        .font(.system(size: 10.5)).foregroundColor(Color(hex: "#8E939C"))
                }
                HStack(spacing: 6) {
                    Figure(title: String(localized: "tools.usage.today", defaultValue: "Today"),
                           value: TokenLedger.compact(ledger.today.tokens), detail: TokenLedger.dollars(ledger.today.cost))
                    Figure(title: String(localized: "tools.usage.7days", defaultValue: "7 days"),
                           value: TokenLedger.compact(ledger.week.tokens), detail: TokenLedger.dollars(ledger.week.cost))
                }
                Text(String(localized: "tools.usage.value", defaultValue: "Tokens written, and what they would cost at API prices."))
                    .font(.system(size: 9.5)).foregroundColor(Color(hex: "#6B7079"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                DayBars(days: ledger.days).frame(height: 54)
                ForEach(ledger.projects, id: \.name) { p in
                    HStack {
                        Text(verbatim: p.name).lineLimit(1).foregroundColor(Color(hex: "#E1E3E6"))
                        Spacer()
                        Text(verbatim: "\(Int((p.share * 100).rounded())) %").foregroundColor(Color(hex: "#8E939C"))
                    }
                    .font(.system(size: 10.5))
                }
                if !ledger.models.isEmpty {
                    Text(verbatim: ledger.models.map { "\($0.name) \(Int(($0.share * 100).rounded())) %" }.joined(separator: " · "))
                        .font(.system(size: 10)).foregroundColor(Color(hex: "#6B7079"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { if active { refresh() } }
        .onChange(of: active) { _, now in if now { refresh() } }
    }

    private func refresh() {
        ledger.refresh()
        state.refreshClaudeAccountUsage()
    }
}

struct Ring: View {
    let share: Double
    let color: Color
    var width: CGFloat = 4
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: width)
            Circle().trim(from: 0, to: min(1, max(0, share)))
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

private struct WindowLine: View {
    let title: String
    let window: PlanWindow?
    let color: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                Circle().fill(Color(hex: color)).frame(width: 6, height: 6)
                Text(title).font(.system(size: 11)).foregroundColor(Color(hex: "#E1E3E6"))
                Text(verbatim: window.map { "\(Int(ClaudePlanGauge.effectivePct($0).rounded())) %" } ?? "—")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8"))
            }
            if let w = window, w.resetsAt > Date() {
                Text(String(format: String(localized: "tools.usage.resets %@", defaultValue: "resets in %@"),
                            TokenLedger.span(w.resetsAt.timeIntervalSinceNow)))
                    .font(.system(size: 9.5)).foregroundColor(Color(hex: "#6B7079"))
            }
        }
    }
}

private struct Figure: View {
    let title: String
    let value: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 9.5)).foregroundColor(Color(hex: "#6B7079"))
            Text(verbatim: value).font(.system(size: 14, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8"))
            Text(verbatim: detail).font(.system(size: 10)).foregroundColor(RafiqLook.gold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.white.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct DayBars: View {
    let days: [(day: Date, cost: Double)]
    var body: some View {
        let top = max(days.map(\.cost).max() ?? 0, 0.01)
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, d in
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: "#E49378").opacity(index == days.count - 1 ? 1 : 0.5))
                        .frame(height: max(2, 38 * d.cost / top))
                    Text(verbatim: String(d.day.formatted(.dateTime.weekday(.narrow))))
                        .font(.system(size: 8.5)).foregroundColor(Color(hex: "#6B7079"))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
#endif
