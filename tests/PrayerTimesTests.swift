import Foundation

// Checks for PrayerTimesEngine: the times of a few places against reference timetables
// (the same algorithm as PrayTimes.org, checked against the adhan library within a minute),
// high latitudes, Ramadan, the next prayer, reminders after a sleep, and the qibla.
//   bash scripts/test-prayer-times.sh

@main
enum PrayerTimesTests {

    nonisolated(unsafe) static var failures = 0

    static func check(_ label: String, _ got: Bool, _ detail: String = "") {
        if got { print("  ✓ \(label)") }
        else   { print("  ✗ \(label) \(detail)"); failures += 1 }
    }

    /// "HH:mm" in a time zone.
    static func hm(_ date: Date?, _ tz: String) -> String {
        guard let date else { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: tz)
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    static func times(_ name: String, lat: Double, lng: Double, tz: String,
                      _ method: PrayerMethod, asr: AsrSchool = .standard, high: HighLatitudeRule = .angleBased,
                      date: (Int, Int, Int), ramadan: Bool = false, expect: [String]) {
        let loc = PrayerLocation(name: name, latitude: lat, longitude: lng, timeZoneId: tz)
        let config = PrayerConfig(method: method, asr: asr, highLatitude: high)
        let day = PrayerTimesEngine.day(year: date.0, month: date.1, day: date.2, location: loc,
                                        config: config, ramadan: ramadan)
        let got = Prayer.allCases.map { hm(day.time($0), tz) }
        check("\(name) \(date.0)-\(date.1)-\(date.2)", got == expect, "got \(got) expected \(expect)")
    }

    static func main() {
        print("\nTimes (fajr, sunrise, dhuhr, asr, maghrib, isha)")
        times("Paris UOIF", lat: 48.8566, lng: 2.3522, tz: "Europe/Paris", .franceUOIF, date: (2026, 11, 11),
              expect: ["06:41", "07:53", "12:35", "14:52", "17:15", "18:28"])
        times("Jakarta Kemenag", lat: -6.2088, lng: 106.8456, tz: "Asia/Jakarta", .indonesia, date: (2026, 10, 15),
              expect: ["04:15", "05:29", "11:40", "14:46", "17:48", "18:58"])
        times("Makkah", lat: 21.4225, lng: 39.8262, tz: "Asia/Riyadh", .ummAlQura, date: (2026, 11, 11),
              expect: ["05:10", "06:29", "12:05", "15:17", "17:40", "19:10"])
        times("Makkah in Ramadan", lat: 21.4225, lng: 39.8262, tz: "Asia/Riyadh", .ummAlQura, date: (2027, 2, 20),
              ramadan: true, expect: ["05:32", "06:48", "12:34", "15:53", "18:21", "20:21"])
        times("Istanbul Diyanet", lat: 41.0082, lng: 28.9784, tz: "Europe/Istanbul", .turkey, date: (2026, 3, 20),
              expect: ["05:36", "07:01", "13:17", "16:41", "19:23", "20:43"])
        times("Karachi Hanafi", lat: 24.8607, lng: 67.0011, tz: "Asia/Karachi", .karachi, asr: .hanafi, date: (2026, 7, 1),
              expect: ["04:17", "05:46", "12:36", "17:18", "19:26", "20:54"])
        times("Tehran", lat: 35.6892, lng: 51.3890, tz: "Asia/Tehran", .tehran, date: (2026, 9, 1),
              expect: ["04:09", "05:36", "12:04", "15:43", "18:51", "19:39"])
        times("Auckland", lat: -36.8485, lng: 174.7633, tz: "Pacific/Auckland", .muslimWorldLeague, date: (2026, 1, 10),
              expect: ["04:24", "06:13", "13:28", "17:19", "20:43", "22:25"])
        times("Honolulu", lat: 21.3069, lng: -157.8583, tz: "Pacific/Honolulu", .northAmerica, date: (2026, 12, 25),
              expect: ["06:01", "07:06", "12:32", "15:36", "17:57", "19:03"])

        print("\nHigh latitudes: Oslo at midsummer, where the sun never goes 18° down")
        times("Oslo angle based", lat: 59.9139, lng: 10.7522, tz: "Europe/Oslo", .muslimWorldLeague, date: (2026, 6, 21),
              expect: ["02:21", "03:54", "13:19", "18:00", "22:44", "00:12"])
        times("Oslo middle of the night", lat: 59.9139, lng: 10.7522, tz: "Europe/Oslo", .muslimWorldLeague,
              high: .middleOfNight, date: (2026, 6, 21),
              expect: ["01:19", "03:54", "13:19", "18:00", "22:44", "01:19"])

        print("\nYour own offsets")
        do {
            let loc = PrayerCities.named("Paris")!.location
            var config = PrayerConfig(method: .franceUOIF)
            config.adjustments = [.fajr: 5, .isha: -3]
            let day = PrayerTimesEngine.day(year: 2026, month: 11, day: 11, location: loc, config: config)
            check("fajr +5, isha −3", hm(day.time(.fajr), "Europe/Paris") == "06:46" && hm(day.time(.isha), "Europe/Paris") == "18:25")
        }

        print("\nThe day of a moment, in the place's time zone")
        do {
            let loc = PrayerCities.named("Jakarta")!.location
            // 2026-10-14 20:00 UTC is already the 15th in Jakarta (UTC+7).
            let moment = Date(timeIntervalSince1970: 1_792_008_000)
            let day = PrayerTimesEngine.day(containing: moment, location: loc, config: PrayerConfig(method: .indonesia))
            check("Jakarta's 15 October", day.year == 2026 && day.month == 10 && day.day == 15, "\(day.year)-\(day.month)-\(day.day)")
            let next = PrayerTimesEngine.dayAfter(moment, location: loc, config: PrayerConfig(method: .indonesia))
            check("then the 16th", next.day == 16)
        }

        print("\nNext and current prayer")
        do {
            let loc = PrayerCities.named("Paris")!.location
            let config = PrayerConfig(method: .franceUOIF)
            let today = PrayerTimesEngine.day(year: 2026, month: 11, day: 11, location: loc, config: config)
            let tomorrow = PrayerTimesEngine.day(year: 2026, month: 11, day: 12, location: loc, config: config)
            let days = [today, tomorrow]
            let asr = today.time(.asr)!
            let next = PrayerTimesEngine.next(after: asr.addingTimeInterval(-60), in: days)
            check("next is Asr a minute before", next?.prayer == .asr)
            check("Asr is current at its time", PrayerTimesEngine.current(at: asr, in: days)?.prayer == .asr)
            check("next after Asr is Maghrib", PrayerTimesEngine.next(after: asr, in: days)?.prayer == .maghrib)
            let late = today.time(.isha)!.addingTimeInterval(3600)
            check("after Isha, tomorrow's Fajr", PrayerTimesEngine.next(after: late, in: days).map { $0.at == tomorrow.time(.fajr) } == true)
            let afterSunrise = today.time(.sunrise)!.addingTimeInterval(60)
            check("no current prayer after sunrise", PrayerTimesEngine.current(at: afterSunrise, in: days) == nil)
            check("sunrise is never announced", !PrayerTimesEngine.events(in: days, reminderMinutes: 10).contains { $0.prayer == .sunrise })

            print("\nReminders and adhan")
            let events = PrayerTimesEngine.events(in: days, reminderMinutes: 10)
            check("two events per prayer", events.count == 20)
            check("in order", events == events.sorted { $0.at < $1.at })
            check("no reminders at 0", PrayerTimesEngine.events(in: days, reminderMinutes: 0).count == 10)
            let maghrib = today.time(.maghrib)!
            let reminder = PrayerTimesEngine.due(in: events, after: maghrib.addingTimeInterval(-700),
                                                 now: maghrib.addingTimeInterval(-599))
            check("reminder 10 min before", reminder?.kind == .reminder && reminder?.prayer == .maghrib)
            let adhan = PrayerTimesEngine.due(in: events, after: maghrib.addingTimeInterval(-60), now: maghrib.addingTimeInterval(1))
            check("adhan at the time", adhan?.kind == .adhan && adhan?.prayer == .maghrib)
            let both = PrayerTimesEngine.due(in: events, after: maghrib.addingTimeInterval(-900), now: maghrib.addingTimeInterval(30))
            check("woken after both: only the adhan", both?.kind == .adhan)
            let stale = PrayerTimesEngine.due(in: events, after: maghrib.addingTimeInterval(-60), now: maghrib.addingTimeInterval(3600))
            check("an hour late: nothing", stale == nil)
            let nothing = PrayerTimesEngine.due(in: events, after: maghrib, now: maghrib.addingTimeInterval(60))
            check("announced once", nothing == nil)

            print("\nSun")
            check("sun at noon is in the sky", (PrayerTimesEngine.sunProgress(at: today.time(.dhuhr)!, day: today) ?? 0) > 0.4)
            check("no sun at night", PrayerTimesEngine.sunProgress(at: late, day: today) == nil)
        }

        print("\nQibla")
        let paris = PrayerTimesEngine.qibla(latitude: 48.8566, longitude: 2.3522)
        check("Paris 119° SE", abs(paris - 119.16) < 0.05 && PrayerTimesEngine.compassPoint(paris) == "SE", "\(paris)")
        let ny = PrayerTimesEngine.qibla(latitude: 40.7128, longitude: -74.006)
        check("New York 58° NE", abs(ny - 58.48) < 0.05 && PrayerTimesEngine.compassPoint(ny) == "NE", "\(ny)")
        let jakarta = PrayerTimesEngine.qibla(latitude: -6.2088, longitude: 106.8456)
        check("Jakarta 295° W/NW", abs(jakarta - 295.15) < 0.05, "\(jakarta)")

        print("\nSettings")
        check("every city has a valid place", PrayerCities.all.allSatisfy { $0.location.isValid && TimeZone(identifier: $0.timeZoneId) != nil })
        check("city names are unique", Set(PrayerCities.all.map(\.name)).count == PrayerCities.all.count)
        check("Paris time zone picks UOIF", PrayerMethod.recommended(forTimeZone: "Europe/Paris") == .franceUOIF)
        check("Chicago picks ISNA", PrayerMethod.recommended(forTimeZone: "America/Chicago") == .northAmerica)
        check("elsewhere, Muslim World League", PrayerMethod.recommended(forTimeZone: "Asia/Tokyo") == .muslimWorldLeague)
        check("reminder clamps", PrayerSettings.clampReminder(-5) == 0 && PrayerSettings.clampReminder(90) == 60)
        check("offsets clamp", PrayerSettings.clampAdjustment(-99) == -30 && PrayerSettings.clampAdjustment(45) == 30)

        print(failures == 0 ? "\nAll prayer time checks passed." : "\n\(failures) check(s) failed.")
        exit(failures == 0 ? 0 : 1)
    }
}
