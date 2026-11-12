#if !APPSTORE
import AppKit
import EventKit
import Foundation
import ScreenCaptureKit
import Vision

// MARK: - Jarvis on the Mac: Shortcuts, calendar, the screen, the Mac itself
//
// More of what Rafiq's on-device brain can do, each on this Mac only:
// - the user's Shortcuts (the Home app's devices, Messages, anything they built), run by name;
// - Calendar and Reminders (EventKit): the agenda, a new event or reminder;
// - the screen: a capture of the front window's display, its text read on the Mac (Vision),
//   for "what's wrong here", "sum up this page" — nothing is kept or sent;
// - the Mac: open an app or a file (Spotlight), the volume, a timer, a web search in the browser.
// macOS asks once for each permission (Calendars, Reminders, Screen Recording).

@MainActor
enum JarvisMac {
    // MARK: Shortcuts

    nonisolated static func shortcutNames() -> [String] {
        let out = run("/usr/bin/shortcuts", ["list"]) ?? ""
        return out.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Runs the user's shortcut whose name matches best; its output, if any, comes back.
    nonisolated static func runShortcut(_ wanted: String, input: String) -> String {
        let names = shortcutNames()
        guard !names.isEmpty else { return String(localized: "jarvis.shortcuts.none", defaultValue: "You have no Shortcuts.") }
        let fold = { (s: String) in s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        let w = fold(wanted)
        guard let name = names.first(where: { fold($0) == w })
                ?? names.first(where: { fold($0).contains(w) || w.contains(fold($0)) }) else {
            return String(format: String(localized: "jarvis.shortcut.unknown %@ %@", defaultValue: "No shortcut called %@. You have: %@."), wanted, names.joined(separator: ", "))
        }
        var args = ["run", name]
        var tmp: URL?
        if !input.trimmingCharacters(in: .whitespaces).isEmpty {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("rafiq-shortcut-\(UUID().uuidString).txt")
            try? input.write(to: url, atomically: true, encoding: .utf8)
            args += ["--input-path", url.path]
            tmp = url
        }
        let out = run("/usr/bin/shortcuts", args, timeout: 60)
        if let tmp { try? FileManager.default.removeItem(at: tmp) }
        guard let out else { return String(format: String(localized: "jarvis.shortcut.failed %@", defaultValue: "The shortcut %@ didn't work."), name) }
        let text = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? String(format: String(localized: "jarvis.shortcut.ran %@", defaultValue: "Done: %@."), name) : String(format: String(localized: "jarvis.shortcut.returned %@ %@", defaultValue: "%@: %@"), name, String(text.prefix(400)))
    }

    // MARK: Calendar and reminders

    private static let store = EKEventStore()

    private static func access(_ type: EKEntityType) async -> Bool {
        switch EKEventStore.authorizationStatus(for: type) {
        case .fullAccess: return true
        case .notDetermined:
            return (try? await (type == .event ? store.requestFullAccessToEvents() : store.requestFullAccessToReminders())) ?? false
        default: return false
        }
    }

    static func agenda(day: String) async -> String {
        guard await access(.event) else { return final(String(localized: "jarvis.calendar.permission", defaultValue: "I don't have access to your Calendar: allow Rafiq in System Settings → Privacy & Security → Calendars.")) }
        let cal = Calendar.current
        let base: Date
        switch day.lowercased() {
        case "tomorrow": base = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        case "today", "": base = Date()
        default: base = parseDate(day) ?? Date()
        }
        let start = cal.startOfDay(for: base)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
            .filter { !$0.isAllDay || true }.sorted { $0.startDate < $1.startDate }
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
        let dayName = DateFormatter.localizedString(from: start, dateStyle: .full, timeStyle: .none)
        guard !events.isEmpty else { return String(format: String(localized: "jarvis.agenda.empty %@", defaultValue: "Nothing in your calendar on %@."), dayName) }
        return String(format: String(localized: "jarvis.agenda.list %@ %@", defaultValue: "%@: %@."), dayName, events.prefix(10).map { e in
            (e.isAllDay ? String(localized: "jarvis.agenda.all-day", defaultValue: "all day") : f.string(from: e.startDate)) + " " + (e.title ?? "—") + (e.location.map { " (\($0))" } ?? "")
        }.joined(separator: ", "))
    }

    static func addEvent(title: String, start: String, minutes: Int) async -> String {
        guard await access(.event) else { return final(String(localized: "jarvis.calendar.permission", defaultValue: "I don't have access to your Calendar: allow Rafiq in System Settings → Privacy & Security → Calendars.")) }
        guard let date = parseDate(start) else { return String(localized: "jarvis.event.need-date", defaultValue: "Tell me the day and the time.") }
        let e = EKEvent(eventStore: store)
        e.title = title
        e.startDate = date
        e.endDate = date.addingTimeInterval(Double(max(5, minutes)) * 60)
        e.calendar = store.defaultCalendarForNewEvents
        do { try store.save(e, span: .thisEvent) } catch { return String(format: String(localized: "jarvis.add.failed %@", defaultValue: "I couldn't add it: %@"), error.localizedDescription) }
        return String(format: String(localized: "jarvis.event.added %@ %@", defaultValue: "Added “%@”, %@."), title, DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short))
    }

    static func addReminder(title: String, due: String) async -> String {
        guard await access(.reminder) else { return final(String(localized: "jarvis.reminders.permission", defaultValue: "I don't have access to your Reminders: allow Rafiq in System Settings → Privacy & Security → Reminders.")) }
        let r = EKReminder(eventStore: store)
        r.title = title
        r.calendar = store.defaultCalendarForNewReminders()
        if let date = parseDate(due) {
            r.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            r.addAlarm(EKAlarm(absoluteDate: date))
        }
        do { try store.save(r, commit: true) } catch { return String(format: String(localized: "jarvis.add.failed %@", defaultValue: "I couldn't add it: %@"), error.localizedDescription) }
        return parseDate(due).map { String(format: String(localized: "jarvis.reminder.added-at %@ %@", defaultValue: "Reminder added: “%@”, %@."), title, DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .short)) } ?? String(format: String(localized: "jarvis.reminder.added %@", defaultValue: "Reminder added: “%@”."), title)
    }

    static func reminders() async -> String {
        guard await access(.reminder) else { return final(String(localized: "jarvis.reminders.permission", defaultValue: "I don't have access to your Reminders: allow Rafiq in System Settings → Privacy & Security → Reminders.")) }
        let pred = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let items: [String] = await withCheckedContinuation { cont in
            store.fetchReminders(matching: pred) { list in
                cont.resume(returning: (list ?? []).prefix(10).map { $0.title ?? "—" })
            }
        }
        return items.isEmpty ? String(localized: "jarvis.reminders.none", defaultValue: "No reminder left.") : String(format: String(localized: "jarvis.reminders.list %@", defaultValue: "Your reminders: %@."), items.joined(separator: ", "))
    }

    /// "2026-11-13 15:00", "15:00" (today, or tomorrow when past), "2026-11-13".
    nonisolated static func parseDate(_ text: String) -> Date? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"] {
            f.dateFormat = format
            if let d = f.date(from: t) { return d }
        }
        f.dateFormat = "HH:mm"
        if let time = f.date(from: t) {
            let cal = Calendar.current
            let c = cal.dateComponents([.hour, .minute], from: time)
            var d = cal.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0, second: 0, of: Date()) ?? Date()
            if d < Date() { d = cal.date(byAdding: .day, value: 1, to: d) ?? d }
            return d
        }
        return nil
    }

    // MARK: The screen

    /// The front app, its window title, and the text on the display it is on (read on the Mac).
    static func screenText() async -> String {
        // The topmost normal window of another app (Rafiq's own island and panels don't count).
        let me = ProcessInfo.processInfo.processIdentifier
        let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        let top = list.first { info in
            (info[kCGWindowLayer as String] as? Int) == 0 && (info[kCGWindowOwnerPID as String] as? pid_t) != me
                && ((info[kCGWindowBounds as String] as? [String: CGFloat])?["Width"] ?? 0) > 200
        }
        let topID = top?[kCGWindowNumber as String] as? CGWindowID
        let appName = top?[kCGWindowOwnerName as String] as? String ?? "?"
        var head = "Front app: \(appName)."
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let front = content.windows.first { $0.windowID == topID }
            if let title = front?.title, !title.isEmpty { head += " Window: \(title)." }
            guard let window = front else { return head + " No window to read." }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width * 2)
            config.height = Int(window.frame.height * 2)
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let text = await Task.detached { recognize(image) }.value
            return head + " Text in the window: " + String(text.prefix(2400))
        } catch {
            return JarvisMac.final(String(localized: "jarvis.screen.permission",
                defaultValue: "I can't see your screen yet: allow Rafiq in System Settings → Privacy & Security → Screen & System Audio Recording, then ask again."))
        }
    }

    nonisolated private static func recognize(_ image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    // MARK: The Mac

    static func openApp(_ name: String) -> String {
        let ok = run("/usr/bin/open", ["-a", name]) != nil
        return ok ? String(format: String(localized: "jarvis.app.opened %@", defaultValue: "Opening %@."), name) : String(format: String(localized: "jarvis.app.unknown %@", defaultValue: "I can't find an app called %@."), name)
    }

    /// Spotlight: the files whose name matches, newest first; `open` opens the first.
    static func findFiles(_ query: String, open: Bool) -> String {
        let out = run("/usr/bin/mdfind", ["-onlyin", NSHomeDirectory(), "-name", query], timeout: 5) ?? ""
        let paths = out.split(separator: "\n").map(String.init)
            .filter { $0.hasPrefix(NSHomeDirectory()) && !$0.contains("/Library/") && !$0.contains("/.") && !$0.contains("/node_modules/") }
            .sorted { (mtime($0) ?? .distantPast) > (mtime($1) ?? .distantPast) }
        guard let first = paths.first else { return String(format: String(localized: "jarvis.file.none %@", defaultValue: "No file called %@."), query) }
        if open { NSWorkspace.shared.open(URL(fileURLWithPath: first)); return String(format: String(localized: "jarvis.file.opened %@", defaultValue: "Opening %@."), (first as NSString).lastPathComponent) }
        let folder = ((first as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath
        return paths.count > 1 ? String(format: String(localized: "jarvis.file.found-more %@ %@ %lld", defaultValue: "Most likely %@, in %@, and %lld other matches."), (first as NSString).lastPathComponent, folder, Int64(paths.count - 1)) : String(format: String(localized: "jarvis.file.found %@ %@", defaultValue: "It's %@, in %@."), (first as NSString).lastPathComponent, folder)
    }

    private static func mtime(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    static func volume(_ level: Int?, mute: Bool?) -> String {
        if let mute {
            _ = run("/usr/bin/osascript", ["-e", "set volume output muted \(mute)"])
            return mute ? String(localized: "jarvis.volume.muted", defaultValue: "Sound muted.") : String(localized: "jarvis.volume.unmuted", defaultValue: "Sound back on.")
        }
        guard let level else { return String(localized: "jarvis.volume.need", defaultValue: "Say a level from 0 to 100.") }
        let v = max(0, min(100, level))
        _ = run("/usr/bin/osascript", ["-e", "set volume output volume \(v)"])
        return String(format: String(localized: "jarvis.volume.level %lld", defaultValue: "Volume at %lld."), Int64(v))
    }

    private static var timers: [DispatchWorkItem] = []

    /// After `minutes`, Rafiq rings and says the label aloud.
    static func timer(minutes: Double, label: String) -> String {
        guard minutes > 0, minutes <= 24 * 60 else { return String(localized: "jarvis.timer.need", defaultValue: "Tell me how many minutes.") }
        let what = label.isEmpty ? String(localized: "jarvis.timer.done", defaultValue: "Time's up.") : label
        let item = DispatchWorkItem {
            SoundEngine.shared.play("finish")
            VoiceSpeaker.shared.say([what], locale: Locale.current)
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
        }
        timers.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + minutes * 60, execute: item)
        return String(format: String(localized: "jarvis.timer.set %@", defaultValue: "Timer set for %@."), PrayerController.countdown(minutes * 60))
    }

    /// A search in the user's browser (Rafiq fetches nothing itself).
    static func webSearch(_ query: String) -> String {
        var c = URLComponents(string: "https://www.google.com/search")!
        c.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = c.url else { return String(localized: "jarvis.web.failed", defaultValue: "I couldn't search that.") }
        NSWorkspace.shared.open(url)
        return String(format: String(localized: "jarvis.web.opened %@", defaultValue: "Searching the web for %@."), query)
    }

    // MARK: Helpers

    /// A message said as it is (a permission to grant): the model doesn't rephrase it.
    static let finalMark = "§"
    static func final(_ text: String) -> String { finalMark + text }

    nonisolated static func run(_ tool: String, _ args: [String], timeout: TimeInterval = 15) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let deadline = DispatchTime.now() + timeout
        DispatchQueue.global().asyncAfter(deadline: deadline) { if p.isRunning { p.terminate() } }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

#endif // !APPSTORE
