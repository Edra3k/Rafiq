import AppKit
import Combine
import Foundation

// MARK: - PrayerQuiet: Rafiq keeps the alerts while you pray
// From a prayer's time until the end of its "now" window (PrayerController.nowWindow), with
// the Prayer pill on and the setting on (default): alerts no longer open the island and
// Rafiq makes no sound. Nothing is answered for the user: approvals and questions simply wait,
// as they would if the user were away. When the window ends, a Digest card says what came
// in, then the waiting approval or question comes up.

@MainActor
final class PrayerQuiet: ObservableObject {
    static let shared = PrayerQuiet()
    static let enabledKey = "prayerQuietAlerts"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    @Published private(set) var isActive = false

    private var prayer: Prayer?
    private var started: Date?
    private var finished = 0
    private var errors = 0
    private var waiting = 0
    private var firstWaitingPill: String?
    private var cancellable: AnyCancellable?

    private init() {
        cancellable = PrayerController.shared.$soon
            .removeDuplicates()
            .sink { [weak self] soon in
                // @Published sends before the value is stored: read it from the argument.
                // `self`, not `.shared`: the first value arrives while `shared` is being made.
                MainActor.assumeIsolated { self?.update(soon) }
            }
    }

    /// Settings changed: start or end the quiet now.
    func settingsChanged() { update(PrayerController.shared.soon) }

    private func update(_ soon: PrayerController.PrayerSoon?) {
        let on = Self.isEnabled && soon?.isNow == true
        if on, !isActive {
            isActive = true
            prayer = soon?.prayer
            started = Date()
            finished = 0; errors = 0; waiting = 0; firstWaitingPill = nil
        } else if !on, isActive {
            end()
        }
    }

    /// An alert came in while quiet (HookServer.expandIfNeeded): counted, not shown.
    func note(_ view: IslandView, pill: String?) {
        switch view {
        case .finished: finished += 1
        case .error: errors += 1
        case .approval, .question:
            waiting += 1
            if firstWaitingPill == nil { firstWaitingPill = pill }
        default: break
        }
    }

    private func end() {
        isActive = false
        let state = AppState.shared
        let minutes = started.map { max(1, Int(Date().timeIntervalSince($0) / 60)) } ?? 0
        if finished + errors + waiting > 0, let prayer {
            let duration = PrayerController.countdown(TimeInterval(minutes * 60))
            DigestCenter.shared.show(Digest(
                kind: .prayer,
                title: String(format: String(localized: "quiet.title %@ %@", defaultValue: "Welcome back · during %@ (%@)"),
                              PrayerController.name(prayer), duration),
                subtitle: String(localized: "quiet.subtitle", defaultValue: "Rafiq kept the alerts. Nothing was answered for you."),
                tiles: [
                    .init(value: "\(finished)", label: String(localized: "quiet.tile.finished", defaultValue: "finished"), tone: finished > 0 ? .good : .plain),
                    .init(value: "\(waiting)", label: String(localized: "quiet.tile.waiting", defaultValue: "waiting for you"), tone: waiting > 0 ? .warn : .plain),
                    .init(value: "\(errors)", label: String(localized: "quiet.tile.errors", defaultValue: "errors"), tone: errors > 0 ? .bad : .plain),
                ],
                primary: firstWaitingPill.map { (String(localized: "quiet.see-waiting", defaultValue: "See what waits"), Digest.Action.focus($0)) }
                    ?? (String(localized: "tasbih.open", defaultValue: "Tasbih"), .tasbih)
            ))
        }
        // What waited comes up now: the approval or the question first, the card after it.
        if state.pendingApproval != nil {
            NotificationCenter.default.post(name: .hookExpand, object: IslandView.approval)
        } else if state.pendingQuestion != nil {
            NotificationCenter.default.post(name: .hookExpand, object: IslandView.question)
        } else {
            DigestCenter.shared.resumeIfWaiting()
        }
        prayer = nil; started = nil
    }
}

// MARK: - EveningBrief: your day, once, in the evening

/// Once a day, 45 minutes after Isha (or at 21:00 without the Prayer pill), if agents worked
/// today: sessions, files, lines, and the prayers checked off. One timer waits for that moment;
/// nothing ticks in between.
@MainActor
final class EveningBrief {
    static let shared = EveningBrief()
    static let enabledKey = "eveningBriefEnabled"
    private let lastDayKey = "eveningBriefLastDay"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    private var timer: Timer?
    private var observer: NSObjectProtocol?

    func start() {
        if observer == nil {
            observer = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { EveningBrief.shared.schedule() }
            }
        }
        schedule()
    }

    func schedule() {
        timer?.invalidate()
        timer = nil
        guard Self.isEnabled else { return }
        let now = Date()
        let target = briefTime(on: now)
        // Today's moment passed and not shown yet (the Mac was asleep): show it now.
        if target <= now {
            if !shownToday(now) { fire() }
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
            arm(at: briefTime(on: tomorrow))
        } else {
            arm(at: target)
        }
    }

    private func arm(at date: Date) {
        let t = Timer(fire: date, interval: 0, repeats: false) { _ in
            MainActor.assumeIsolated {
                EveningBrief.shared.fire()
                EveningBrief.shared.schedule()
            }
        }
        t.tolerance = 30
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func briefTime(on day: Date) -> Date {
        let cal = Calendar.current
        let prayer = PrayerController.shared
        if AppState.shared.activeIntegrations.contains(PrayerController.pillId),
           let isha = prayer.days.compactMap({ $0.time(.isha) }).first(where: { cal.isDate($0, inSameDayAs: day) }) {
            return isha.addingTimeInterval(45 * 60)
        }
        return cal.date(bySettingHour: 21, minute: 0, second: 0, of: day) ?? day
    }

    private func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    private func shownToday(_ now: Date) -> Bool {
        UserDefaults.standard.string(forKey: lastDayKey) == dayKey(now)
    }

    /// Shows today's brief (also from Settings, to try it).
    func fire(force: Bool = false) {
        let now = Date()
        guard force || (Self.isEnabled && !shownToday(now)) else { return }
        guard let day = RecapStore.shared.daySummary(on: now) else { return }
        UserDefaults.standard.set(dayKey(now), forKey: lastDayKey)

        let prayer = PrayerController.shared
        let prayerOn = AppState.shared.activeIntegrations.contains(PrayerController.pillId) && prayer.today != nil
        let dateText = DateFormatter.localizedString(from: now, dateStyle: .full, timeStyle: .none)
        var tiles: [Digest.Tile] = [
            .init(value: "\(day.sessions)", label: String(localized: "brief.tile.sessions", defaultValue: "sessions")),
            .init(value: "\(day.files)", label: String(localized: "brief.tile.files", defaultValue: "files changed")),
            .init(value: "+\(day.linesAdded)", label: String(localized: "brief.tile.lines", defaultValue: "lines added"), tone: .good),
        ]
        if prayerOn {
            tiles.append(.init(value: "\(prayer.prayed.count)/5", label: String(localized: "brief.tile.prayers", defaultValue: "prayers"), tone: .gold))
        }
        var subtitle = String(format: String(localized: "brief.work %@", defaultValue: "%@ of agent work"),
                              PrayerController.countdown(TimeInterval(day.minutes * 60)))
        if let project = day.topProject, !project.isEmpty {
            subtitle += " · " + String(format: String(localized: "brief.mostly %@", defaultValue: "mostly on %@"), project)
        }
        var lines: [String] = []
        if prayerOn, let fajr = prayer.tomorrow?.time(.fajr) {
            lines.append(String(format: String(localized: "brief.tomorrow %@ %@", defaultValue: "Tomorrow · %@ %@"),
                                PrayerController.name(.fajr), prayer.clock(fajr)))
        }
        DigestCenter.shared.show(Digest(
            kind: .evening,
            title: String(format: String(localized: "brief.title %@", defaultValue: "Your day · %@"), dateText),
            subtitle: subtitle,
            tiles: tiles,
            lines: lines
        ))
    }
}
