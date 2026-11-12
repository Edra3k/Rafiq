import AppKit
import Foundation

// MARK: - MorningBrief: the day ahead, once, in the morning — shown and said aloud
//
// The first time you are at the Mac after Fajr (05:00 without the Prayer pill) and before noon:
// the next prayer, what the agents finished overnight and what waits for you, the home server,
// the projects with commits to push. A Digest card (buttons only open or dismiss), and the same
// in a few sentences with Rafiq's voice (Settings → General, both on by default).

@MainActor
final class MorningBrief {
    static let shared = MorningBrief()
    static let enabledKey = "morningBriefEnabled"
    static let speakKey = "morningBriefSpeak"
    private let lastDayKey = "morningBriefLastDay"

    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
    static var speaks: Bool { UserDefaults.standard.object(forKey: speakKey) as? Bool ?? true }

    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    /// Checks on wake, on unlock and every 10 minutes (nothing ticks faster).
    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 600, repeats: true) { _ in
            MainActor.assumeIsolated { MorningBrief.shared.check() }
        }
        t.tolerance = 60
        RunLoop.main.add(t, forMode: .common)
        timer = t
        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { MorningBrief.shared.checkSoon() }
        })
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { MorningBrief.shared.checkSoon() }
        })
        checkSoon()
    }

    /// A few seconds after waking or unlocking: the Mac and the island have settled.
    private func checkSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            MainActor.assumeIsolated { MorningBrief.shared.check() }
        }
    }

    private func check() {
        let now = Date()
        guard Self.isEnabled, !shownToday(now), !PrayerQuiet.shared.isActive else { return }
        guard now >= startTime(on: now), Calendar.current.component(.hour, from: now) < 12 else { return }
        // Someone is at the Mac (it was used in the last minute).
        guard AgentShield.idleSeconds() < 60 else { return }
        fire()
    }

    /// Fajr when the Prayer pill knows it, else 05:00.
    private func startTime(on day: Date) -> Date {
        let cal = Calendar.current
        if AppState.shared.activeIntegrations.contains(PrayerController.pillId),
           let fajr = PrayerController.shared.today?.time(.fajr), cal.isDate(fajr, inSameDayAs: day) {
            return fajr
        }
        return cal.date(bySettingHour: 5, minute: 0, second: 0, of: day) ?? day
    }

    private func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    private func shownToday(_ now: Date) -> Bool {
        UserDefaults.standard.string(forKey: lastDayKey) == dayKey(now)
    }

    /// Shows this morning's brief (also from Settings, to try it).
    func fire(force: Bool = false) {
        let now = Date()
        guard force || !shownToday(now) else { return }
        UserDefaults.standard.set(dayKey(now), forKey: lastDayKey)
        #if !APPSTORE
        for project in SessionLauncher.shared.projects.prefix(8) { GitStatusStore.shared.refresh(project, force: true) }
        #endif
        // Git answers in the background: the card a moment later, with what it found.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            MainActor.assumeIsolated { MorningBrief.shared.compose(at: now) }
        }
    }

    private func compose(at now: Date) {
        let cal = Calendar.current
        let state = AppState.shared
        let prayer = PrayerController.shared
        let prayerOn = state.activeIntegrations.contains(PrayerController.pillId) && prayer.today != nil
        let since = cal.date(bySettingHour: 20, minute: 0, second: 0, of: cal.date(byAdding: .day, value: -1, to: now) ?? now) ?? now
        let overnight = TurnLog.shared.turns(from: since, to: now)
        let waiting = state.pendingApproval.map { $0.queueCount } ?? 0

        var tiles: [Digest.Tile] = []
        var said: [String] = []
        var lines: [String] = []

        // The next prayer.
        if prayerOn, let next = prayer.next(at: now) {
            tiles.append(.init(value: prayer.clock(next.at), label: PrayerController.name(next.prayer), tone: .gold))
            said.append(String(format: String(localized: "morning.say.prayer %@ %@", defaultValue: "Next prayer: %@ at %@."),
                               PrayerController.name(next.prayer), prayer.clock(next.at)))
        }
        // Overnight.
        tiles.append(.init(value: "\(overnight.count)", label: String(localized: "morning.tile.overnight", defaultValue: "turns overnight"),
                           tone: overnight.isEmpty ? .plain : .good))
        if waiting > 0 {
            tiles.append(.init(value: "\(waiting)", label: String(localized: "quiet.tile.waiting", defaultValue: "waiting for you"), tone: .warn))
        }
        if !overnight.isEmpty || waiting > 0 {
            said.append(String(format: String(localized: "morning.say.agents %lld %lld",
                                              defaultValue: "Overnight, %lld turns finished; %lld requests wait for your OK."),
                               Int64(overnight.count), Int64(waiting)))
        }
        for turn in overnight.suffix(3).reversed() {
            lines.append("\(turn.project) · « \(turn.prompt.prefix(60)) »")
        }
        // The home server.
        #if !APPSTORE
        let lab = Homelab.shared
        if let updated = lab.lastUpdate, now.timeIntervalSince(updated) < 3600, let fullest = lab.storages.max(by: { $0.share < $1.share }) {
            let pct = Int((fullest.share * 100).rounded())
            let online = lab.nodes.allSatisfy(\.online)
            tiles.append(.init(value: "\(pct) %", label: String(format: String(localized: "morning.tile.disk %@", defaultValue: "disk · %@"), fullest.name),
                               tone: pct >= 90 || !online ? .bad : pct >= 80 ? .warn : .plain))
            said.append(online
                ? String(format: String(localized: "morning.say.server %lld", defaultValue: "The server is up, its fullest disk at %lld percent."), Int64(pct))
                : String(localized: "morning.say.server-down", defaultValue: "A server node is offline."))
        }
        // Commits to push.
        var toPush: [String] = []
        for project in SessionLauncher.shared.projects {
            if let g = GitStatusStore.shared.summary(for: project), g.ahead > 0 {
                toPush.append("\(SessionLauncher.name(of: project)) ↑\(g.ahead)")
            }
        }
        if !toPush.isEmpty {
            tiles.append(.init(value: "\(toPush.count)", label: String(localized: "morning.tile.push", defaultValue: "to push"), tone: .warn))
            lines.append(String(format: String(localized: "morning.push %@", defaultValue: "To push: %@"), toPush.prefix(3).joined(separator: " · ")))
            said.append(String(format: String(localized: "morning.say.push %lld", defaultValue: "%lld projects have commits to push."), Int64(toPush.count)))
        }
        #endif

        let name = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        let hello = name.isEmpty
            ? String(localized: "morning.hello", defaultValue: "Good morning")
            : String(format: String(localized: "morning.hello %@", defaultValue: "Good morning, %@"), name)
        let dateText = DateFormatter.localizedString(from: now, dateStyle: .full, timeStyle: .none)
        var primary: (label: String, action: Digest.Action)? = nil
        if let asking = state.pendingApproval?.pillId {
            primary = (String(localized: "morning.see-request", defaultValue: "See the request"), .focus(asking))
        }
        DigestCenter.shared.show(Digest(kind: .morning, title: hello, subtitle: dateText,
                                        tiles: Array(tiles.prefix(4)), lines: lines, primary: primary))
        #if !APPSTORE
        if Self.speaks && state.soundEnabled {
            VoiceSpeaker.shared.say([hello + "."] + (said.isEmpty
                ? [String(localized: "morning.say.calm", defaultValue: "Nothing waits for you. Have a good day.")]
                : said), locale: Locale.current)
        }
        #endif
    }
}
