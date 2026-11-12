import AppKit
import AVFoundation
import Combine
import Foundation

/// Prayer times: today's five prayers, a reminder a few minutes before each one, and the
/// island opening at the time itself (with the music paused and, if the user dropped one in
/// the sounds folder, their own adhan). Everything is calculated on the Mac: no network.
/// One timer waits for the next reminder, prayer or midnight (nothing ticks in between, so
/// Rafiq stays at 0 % CPU while hidden); the card and the pill draw from the stored times.
@MainActor
final class PrayerController: ObservableObject {
    static let shared = PrayerController()
    nonisolated static let pillId = PrayerSettings.pillId

    @Published private(set) var location: PrayerLocation?
    @Published private(set) var today: PrayerDay?
    @Published private(set) var tomorrow: PrayerDay?
    /// The prayers checked off today.
    @Published private(set) var prayed: Set<Prayer> = []
    @Published private(set) var adhanPlaying = false
    /// A prayer inside its reminder window, or one whose time just came (the "now" window):
    /// the notch's halo and ear show it. Changes only on the controller's own timer.
    @Published private(set) var soon: PrayerSoon?

    struct PrayerSoon: Equatable {
        let prayer: Prayer
        let at: Date
        let isNow: Bool
        /// Ramadan: Maghrib is the iftar and Fajr the end of the suhur, announced earlier.
        var ramadan: Bool = false
    }

    // MARK: - Ramadan

    /// How long before the iftar (Maghrib) and the end of the suhur (Fajr) the notch counts down.
    static let ramadanWindow: TimeInterval = 2 * 3600

    /// The Hijri month and day at `date` where the location is (Umm al-Qura).
    func hijriMonthDay(at date: Date) -> (month: Int, day: Int) {
        var calendar = Calendar(identifier: .islamicUmmAlQura)
        calendar.timeZone = location?.timeZone ?? .current
        let c = calendar.dateComponents([.month, .day], from: date)
        return (c.month ?? 0, c.day ?? 0)
    }

    func isRamadan(at date: Date) -> Bool { hijriMonthDay(at: date).month == 9 }

    /// The left ear: "Iftar · 42 min", "Suhur · 1 h 10 min" in Ramadan, else the pill's label.
    func earLabel(at date: Date) -> String {
        if let soon, soon.ramadan, !soon.isNow {
            let left = Self.countdown(soon.at.timeIntervalSince(date))
            if soon.prayer == .maghrib {
                return String(format: String(localized: "ramadan.iftar %@", defaultValue: "Iftar · %@"), left)
            }
            if soon.prayer == .fajr {
                return String(format: String(localized: "ramadan.suhur %@", defaultValue: "Suhur · %@"), left)
            }
        }
        return pillLabel(at: date)
    }

    private var timer: Timer?
    /// Events up to this instant have been handled. Starts now: nothing is replayed at launch.
    private var handledUntil = Date()
    private var cancellables = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []
    private var adhanPlayer: AVAudioPlayer?
    private var adhanToken: UUID?

    private var isPillActive: Bool {
        AppState.shared.activeIntegrations.contains(Self.pillId)
    }

    private init() {
        AppState.shared.$activeIntegrations
            .map { $0.contains(Self.pillId) }
            .removeDuplicates()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updatePolling() }
            }
            .store(in: &cancellables)

        // After a sleep, a clock change or a new time zone, catch up and wait for the right moment again.
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { PrayerController.shared.tick() }
        })
        for name in [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange, .NSCalendarDayChanged] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { PrayerController.shared.settingsChanged() }
            })
        }
    }

    func start() {
        updatePolling()
        _ = PrayerQuiet.shared
        EveningBrief.shared.start()
        MorningBrief.shared.start()
        _ = FocusMode.shared
    }

    /// A setting changed: new times (also for the preview in Settings while the pill is off),
    /// same announcements already made.
    func settingsChanged() {
        recompute()
        guard isPillActive else { return }
        tick()
    }

    // MARK: - Reading

    /// Today's and tomorrow's times, for the next prayer after the last one of the day.
    var days: [PrayerDay] { [today, tomorrow].compactMap { $0 } }

    func next(at date: Date) -> (prayer: Prayer, at: Date)? {
        PrayerTimesEngine.next(after: date, in: days)
    }

    func current(at date: Date) -> (prayer: Prayer, at: Date)? {
        PrayerTimesEngine.current(at: date, in: days)
    }

    /// What the pill capsule says: "Maghrib 17:48", "Maghrib · 8 min" in the reminder window,
    /// "Maghrib · now" for the first minutes of a prayer.
    func pillLabel(at date: Date) -> String {
        guard location != nil else { return Self.title }
        if let now = current(at: date), date.timeIntervalSince(now.at) < Self.nowWindow {
            return String(format: String(localized: "prayer.pill.now %@", defaultValue: "%@ · now"),
                          Self.name(now.prayer))
        }
        guard let next = next(at: date) else { return Self.title }
        let left = next.at.timeIntervalSince(date)
        let reminder = TimeInterval(max(PrayerSettings.reminderMinutes, 0) * 60)
        if reminder > 0, left <= reminder {
            return "\(Self.name(next.prayer)) · \(Self.countdown(left))"
        }
        return "\(Self.name(next.prayer)) \(clock(next.at))"
    }

    /// "17:48" (or "5:48 PM") in the location's time zone.
    func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("jjmm")
        f.timeZone = location?.timeZone ?? .current
        return f.string(from: date)
    }

    /// "1 h 8 min", "8 min", "< 1 min".
    static func countdown(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes < 1 { return String(localized: "prayer.under-a-minute", defaultValue: "< 1 min") }
        let f = DateComponentsFormatter()
        f.allowedUnits = minutes >= 60 ? [.hour, .minute] : [.minute]
        f.unitsStyle = .abbreviated
        return f.string(from: TimeInterval(minutes * 60)) ?? "\(minutes) min"
    }

    /// The Hijri date of today, in the user's language ("21 Jumada I 1448").
    func hijriDate(at date: Date) -> String {
        var calendar = Calendar(identifier: .islamicUmmAlQura)
        calendar.timeZone = location?.timeZone ?? .current
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateStyle = .long
        f.timeStyle = .none
        return f.string(from: date)
    }

    /// "١ جمادى الآخرة": the Hijri day and month, in Arabic, for the notch.
    func hijriShortArabic(at date: Date) -> String {
        var calendar = Calendar(identifier: .islamicUmmAlQura)
        calendar.timeZone = location?.timeZone ?? .current
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "ar-SA")   // Arabic-Indic digits: ١٢
        f.timeZone = calendar.timeZone
        f.dateFormat = "d MMMM"
        return f.string(from: date)
    }

    var qibla: Double? {
        location.map { PrayerTimesEngine.qibla(latitude: $0.latitude, longitude: $0.longitude) }
    }

    // MARK: - Checking off

    func togglePrayed(_ prayer: Prayer) {
        guard prayer.isObligatory, let today else { return }
        if prayed.contains(prayer) { prayed.remove(prayer) } else { prayed.insert(prayer) }
        PrayerSettings.setPrayed(prayed, on: today)
    }

    // MARK: - Adhan

    func stopAdhan() {
        adhanPlayer?.stop()
        adhanPlayer = nil
        adhanPlaying = false
    }

    /// The user's own adhan: adhan.mp3 (or .m4a, .wav…) in Rafiq's sounds folder.
    static var adhanFile: URL? { SoundEngine.customURL(for: "adhan") }

    private func playAdhan() {
        guard PrayerSettings.playAdhan, let url = Self.adhanFile,
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        stopAdhan()
        player.volume = 0.8
        player.prepareToPlay()
        player.play()
        adhanPlayer = player
        adhanPlaying = true
        // No delegate needed: once the file has played, the flag clears (unless another one started).
        let token = UUID()
        adhanToken = token
        let length = player.duration
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((length + 0.5) * 1_000_000_000))
            guard let self, self.adhanToken == token else { return }
            self.stopAdhan()
        }
    }

    // MARK: - Clock

    private func updatePolling() {
        if isPillActive {
            recompute()
            handledUntil = Date()
            scheduleNext()
        } else {
            stopTimer()
            stopAdhan()
            paintIdle()
        }
    }

    private func recompute() {
        let now = Date()
        location = PrayerSettings.location
        guard let location else {
            today = nil
            tomorrow = nil
            prayed = []
            paintIdle()
            return
        }
        let config = PrayerSettings.config
        let t = PrayerTimesEngine.day(containing: now, location: location, config: config)
        today = t
        tomorrow = PrayerTimesEngine.dayAfter(now, location: location, config: config)
        prayed = PrayerSettings.prayed(on: t)
        paintSchedule()
    }

    /// One timer, at the next reminder, prayer or midnight where the location is.
    private func scheduleNext() {
        stopTimer()
        guard isPillActive, let location else { return }
        let now = Date()
        let upcoming = PrayerTimesEngine.events(in: days, reminderMinutes: PrayerSettings.reminderMinutes)
            .first { $0.at > now }?.at
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = location.timeZone
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        // The "now" label on the pill ends a few minutes after a prayer: wake for it too.
        let nowEnds = current(at: now).map { $0.at.addingTimeInterval(Self.nowWindow) }.flatMap { $0 > now ? $0 : nil }
        // Ramadan: wake when the iftar and suhur countdowns start too.
        let ramadanStart = isRamadan(at: now)
            ? days.flatMap { [$0.time(.maghrib), $0.time(.fajr)] }.compactMap { $0 }
                .map { $0.addingTimeInterval(-Self.ramadanWindow) }.filter { $0 > now }.min()
            : nil
        guard let fire = [upcoming, midnight, nowEnds, ramadanStart].compactMap({ $0 }).min() else { return }
        let t = Timer(fire: fire.addingTimeInterval(0.5), interval: 0, repeats: false) { _ in
            MainActor.assumeIsolated {
                PrayerController.shared.timer = nil
                PrayerController.shared.tick()
            }
        }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard isPillActive else { updatePolling(); return }
        let now = Date()
        // A new day where the location is: new times.
        if let today, let location {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = location.timeZone
            let parts = calendar.dateComponents([.year, .month, .day], from: now)
            if parts.year != today.year || parts.month != today.month || parts.day != today.day { recompute() }
        } else {
            recompute()
        }
        let events = PrayerTimesEngine.events(in: days, reminderMinutes: PrayerSettings.reminderMinutes)
        let due = PrayerTimesEngine.due(in: events, after: handledUntil, now: now)
        handledUntil = now
        if let due { surface(due) }
        paintSchedule()
        scheduleNext()
    }

    // MARK: - Pill

    /// The event lands on the Prayer pill. The island opens onto that pill unless a card
    /// the user is in the middle of (an approval, a question, the chat) is already up.
    private func surface(_ event: PrayerEvent) {
        let state = AppState.shared
        if canSurface(in: state) {
            state.focusId = Self.pillId
            if let idx = state.tasks.firstIndex(where: { $0.id == Self.pillId }) {
                state.tasks[idx].pillBadge = nil
            }
            if state.mode != .expanded {
                NotificationCenter.default.post(name: .hookExpand, object: IslandView.overview)
            } else if state.view != .overview {
                state.view = .overview
            }
        } else if state.focusId != Self.pillId {
            state.setPillBadge(.finished, for: Self.pillId)
        }
        switch event.kind {
        case .reminder:
            SoundEngine.shared.play("peek")
        case .adhan:
            if PrayerSettings.pauseMusic { pauseMusic() }
            if PrayerSettings.playAdhan, Self.adhanFile != nil {
                playAdhan()
            } else {
                SoundEngine.shared.play("greeting")
            }
        }
    }

    /// Music, Spotify: paused, not stopped. The user starts them again.
    private func pauseMusic() {
        #if !APPSTORE
        MusicController.shared.pause()
        SpotifyController.shared.pause()
        #endif
    }

    /// Don't take the island away from a card the user is busy in.
    private func canSurface(in state: AppState) -> Bool {
        if state.pendingApproval != nil || state.pendingQuestion != nil { return false }
        if state.mode != .expanded { return true }
        switch state.view {
        case .overview, .empty, .finished, .error: return true
        default: return false
        }
    }

    /// The idle card header of the pill reads the next prayer.
    private func paintSchedule() {
        updateSoon()
        let state = AppState.shared
        guard let idx = state.tasks.firstIndex(where: { $0.id == Self.pillId }) else { return }
        state.tasks[idx].state = .idle
        if let next = next(at: Date()) {
            state.tasks[idx].steps = ["\(Self.name(next.prayer)) \(clock(next.at))"]
        } else {
            state.tasks[idx].steps = []
        }
    }

    /// The reminder window and the "now" window start and end on the timer's own events
    /// (scheduleNext wakes for each), so this stays right without ticking in between.
    private func updateSoon() {
        let now = Date()
        var value: PrayerSoon?
        if isPillActive, location != nil {
            if let current = current(at: now), current.prayer.isObligatory,
               now.timeIntervalSince(current.at) < Self.nowWindow {
                value = PrayerSoon(prayer: current.prayer, at: current.at, isNow: true)
            } else if let next = next(at: now), next.prayer.isObligatory {
                var reminder = TimeInterval(max(PrayerSettings.reminderMinutes, 0) * 60)
                let ramadan = isRamadan(at: now) && (next.prayer == .maghrib || next.prayer == .fajr)
                if ramadan { reminder = max(reminder, Self.ramadanWindow) }
                if reminder > 0, next.at.timeIntervalSince(now) <= reminder + 1 {
                    value = PrayerSoon(prayer: next.prayer, at: next.at, isNow: false, ramadan: ramadan)
                }
            }
        }
        if soon != value { soon = value }
    }

    private func paintIdle() {
        if soon != nil { soon = nil }
        let state = AppState.shared
        guard let idx = state.tasks.firstIndex(where: { $0.id == Self.pillId }) else { return }
        state.tasks[idx].state = .idle
        state.tasks[idx].steps = []
        state.tasks[idx].pillBadge = nil
        if let name = PillCatalog.definition(for: Self.pillId)?.name {
            state.tasks[idx].name = name
        }
    }

    // MARK: - Words

    /// How long "· now" stays on the pill after a prayer's time.
    static let nowWindow: TimeInterval = 15 * 60

    static var title: String { String(localized: "prayer.title", defaultValue: "Prayer") }

    static func name(_ prayer: Prayer) -> String {
        switch prayer {
        case .fajr: return String(localized: "prayer.fajr", defaultValue: "Fajr")
        case .sunrise: return String(localized: "prayer.sunrise", defaultValue: "Sunrise")
        case .dhuhr: return String(localized: "prayer.dhuhr", defaultValue: "Dhuhr")
        case .asr: return String(localized: "prayer.asr", defaultValue: "Asr")
        case .maghrib: return String(localized: "prayer.maghrib", defaultValue: "Maghrib")
        case .isha: return String(localized: "prayer.isha", defaultValue: "Isha")
        }
    }

}
